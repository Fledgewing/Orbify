// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.time.ZoneOffset

class ReadingCardTest {
    private val now=Instant.parse("2026-11-26T12:00:00Z").epochSecond
    private val md5="a".repeat(32)
    private fun fixture(run: (File, Sql) -> Unit) {
        val dir=Files.createTempDirectory("card-fixture").toFile()
        try { JdbcSql(File(dir,"statistics.sqlite3")).use { db ->
            db.exec("CREATE TABLE book(id INTEGER,md5 TEXT)")
            db.exec("CREATE TABLE page_stat_data(id_book INTEGER,page INTEGER,start_time INTEGER,duration INTEGER,total_pages INTEGER)")
            db.exec("INSERT INTO book VALUES(1,?),(2,'other')",md5)
            run(dir,db)
        } } finally { dir.deleteRecursively() }
    }
    @Test fun normalizedPaceSurvivesLayoutChangesAndIgnoresOtherBooksAndInvalidVisits() = fixture { _,db ->
        // Each visit covers one percent of the book, despite different page counts.
        for(i in 1..5) db.exec("INSERT INTO page_stat_data VALUES(1,?,?,60,100)",i,now-i*60)
        val first=ReadingStats.forecast(db,md5,0.5,now,600,ZoneOffset.UTC)
        assertEquals("50 m left",first["time_left"])
        assertEquals("Done by Tue 1 Dec",first["finish_forecast"])
        db.exec("UPDATE page_stat_data SET total_pages=200")
        assertEquals("1 h 40 m left",ReadingStats.forecast(db,md5,0.5,now,600,ZoneOffset.UTC)["time_left"])
        db.exec("INSERT INTO page_stat_data VALUES(2,1,?,600,100),(1,0,?,600,100),(1,1,?,0,100),(1,1,?,99999,100),(1,1,?,60,100)",now-60,now-60,now-60,now-60,now+60)
        assertEquals("1 h 40 m left",ReadingStats.forecast(db,md5,0.5,now,0,ZoneOffset.UTC)["time_left"])
        assertNull(ReadingStats.forecast(db,md5,0.5,now,0,ZoneOffset.UTC)["finish_forecast"])
    }
    @Test fun unknownPaceLocatorAndIdentityNeverProduceAFinishDate() = fixture { _,db ->
        for(i in 1..4) db.exec("INSERT INTO page_stat_data VALUES(1,?,?,60,100)",i,now-i*60)
        assertTrue(ReadingStats.forecast(db,md5,0.5,now,600).isEmpty())
        for(fraction in listOf(null,Double.NaN,-0.1,1.1)) assertTrue(ReadingStats.forecast(db,md5,fraction,now,600).isEmpty())
        assertTrue(ReadingStats.forecast(db,"missing",0.5,now,600).isEmpty())
        assertEquals("Finished",ReadingStats.forecast(db,md5,1.0,now,600)["time_left"])
    }
    @Test fun registryUsesDeviceIdentityAndLocalProgressWithoutATitleJoin() = fixture { dir,db ->
        val file=File(dir,"moon.epub").apply { writeText("fixture") }
        File(dir,"moon.sdr/metadata.epub.lua").apply {
            parentFile!!.mkdirs()
            writeText("return "+String(LuaValue.encode(mapOf("partial_md5_checksum" to md5,"percent_finished" to 0.5)),Charsets.ISO_8859_1))
        }
        for(i in 1..5) db.exec("INSERT INTO page_stat_data VALUES(1,?,?,60,100)",i,now-i*60)
        val source=DevicePersonalReading(listOf(dir),File(dir,"statistics.sqlite3")) { JdbcSql(it) }
        val fallback=object:PersonalReadingSource {
            override val capabilities=emptySet<String>()
            override fun read(kind:String,now:Long)=emptyList<PersonalReadingRecord>()
            override fun card(book:Map<String,Any?>,now:Long,dailySeconds:Long)=mapOf("time_left" to "fallback")
        }
        val row=mapOf("title" to "Same title","local_path" to file.path,"progress" to 10)
        val card=PersonalReading(listOf(source,fallback)).card(row,now,600)
        assertEquals(50.0,card["progress"])
        assertEquals("50 m left",card["time_left"])
        assertEquals("fallback",PersonalReading(listOf(source,fallback)).card(row-"local_path",now,600)["time_left"])
        assertTrue(LuaValue.encode(card).size<LibraryReadModel.MAX_BYTES)
    }
    @Test fun accountRemovalRepublishesBothOwnersWithPaceAndForecast() = removalLifecycle("fixture")
    @Test fun deviceRemovalRepublishesBothOwnersWithPaceAndForecast() = removalLifecycle(DeviceLibrary.OWNER)

    private fun removalLifecycle(commandOwner: String) = fixture { dir, db ->
        val folder=File(dir,"Books").apply { mkdirs() }
        val reading=File(folder,"moon.epub").apply { writeText("fixture") }
        val finished=File(folder,"done.epub").apply { writeText("finished fixture") }
        val sidecar=File(folder,"moon.sdr").apply { mkdirs() }
        val cover=File(sidecar,"cover.jpg").apply { writeText("fixture cover") }
        File(sidecar,"metadata.epub.lua").writeText("return "+String(LuaValue.encode(mapOf(
            "doc_props" to mapOf("title" to "The Moon","series" to "Moon","series_index" to 2),
            "partial_md5_checksum" to md5,"percent_finished" to 0.5)),Charsets.ISO_8859_1))
        File(folder,"done.sdr/metadata.epub.lua").apply {
            parentFile!!.mkdirs()
            writeText("return "+String(LuaValue.encode(mapOf("summary" to mapOf("status" to "complete"))),Charsets.ISO_8859_1))
        }
        for(i in 1..5) db.exec("INSERT INTO page_stat_data VALUES(1,?,?,60,100)",i,now-i*60)
        val root=File(dir,"koreader/settings/orbit-cache").apply { mkdirs() }
        net.fledgewing.orbitcompanion.server.bookorbit.CacheStore(root, {}, { JdbcSql(it) }).use { store ->
            store.setMeta("owner", "fixture")
            val roots=listOf(folder)
            // Independent neutral server adapter: no protocol or production adapter construction.
            val adapter=object: ServerAdapter {
                override val id="fixture"
                override fun localFiles(owner:String)=DeviceLibrary(roots,clock={now}).localFiles(DeviceLibrary.OWNER)
                override fun project(owner:String,request:Map<*,*>)=DeviceLibrary(roots,clock={now}).project(DeviceLibrary.OWNER,request)
            }
            fun request(op:String, extra:Map<String,Any?> = emptyMap())=String(LuaValue.encode(
                mapOf("op" to op,"source" to "all","limit" to 2,"bytes" to 16384)+extra),Charsets.ISO_8859_1)
            val window=request("window")
            val summary=request("storage.summary")
            val battery=request("battery")
            fun result(owner:String,request:String):Map<*,*> {
                val bytes=store.db().query("SELECT body FROM library_views WHERE owner=? AND request=?",owner,request) { it.bytes(0)!! }.single()
                assertTrue(bytes.size<=16384)
                val result=LuaValue.parse(bytes) as Map<*,*>
                assertTrue((result["items"] as? List<*>).orEmpty().size<=2)
                return result
            }
            fun rows(owner:String)=(result(owner,window)["items"] as List<*>).map { it as Map<*,*> }
            fun card(owner:String)=rows(owner).single { it["local_path"]==reading.canonicalPath }
            var aggregates=0
            var level=78
            val accountRequests=mutableListOf<String>()
            val events=mutableListOf<Map<String,Any?>>()
            val owners=listOf("fixture",DeviceLibrary.OWNER)
            val model=LibraryReadModel(store,{now},{},
                readingStats={ aggregates++; mapOf("year" to mapOf("seconds" to List(365) { 600L })) },
                accountStats={ accountRequests+=it; null }, battery={ mapOf("level" to level) }, adapter=adapter,
                personalDevice={ DevicePersonalReading(roots,File(dir,"statistics.sqlite3")) { JdbcSql(it) } },
                changedEvent={ event ->
                    // Delivery happens after the new bounded window has landed.
                    val owner=event["owner"] as String
                    if (!finished.exists()) assertEquals(1, rows(owner).size)
                    events+=event
                })
            for(owner in owners) assertTrue(model.publish(owner,listOf(window,summary,battery,request("reading.stats"))))
            assertEquals(2,aggregates)
            val before=owners.associateWith(::card)
            for(row in before.values) {
                assertEquals(Instant.ofEpochSecond(now).toString(),row["added"])
                assertEquals(cover.path,row["cover_path"])
                assertEquals(true,(row["available"] as Map<*,*>)["cover"])
                assertEquals("Moon · Book 2",LuaValue.utf8(row["series_line"] as String))
                assertEquals("50 m left",row["time_left"])
                assertTrue((row["finish_forecast"] as String).startsWith("Done by "))
                assertEquals("this reader",row["forecast_source"])
                assertEquals(50L,row["progress"])
            }
            val action=(result(commandOwner,summary)["actions"] as List<*>).map { it as Map<*,*> }.single { it["id"]=="finished" }
            events.clear(); level=0
            model.storageCommand(commandOwner,"storage.free",mapOf("action" to "finished","token" to action["token"]))
            assertFalse(finished.exists())
            assertTrue(File(folder,"done.sdr/metadata.epub.lua").isFile)
            assertEquals(4,aggregates) // One fresh aggregate per owner batch, never retained across owners.
            assertEquals(listOf("fixture"),accountRequests)
            assertEquals(owners.toSet(),events.map { it["owner"] }.toSet())
            assertEquals(2,events.size)
            assertTrue(events.all { it["kind"]=="library" })
            for(owner in owners) {
                assertEquals(before[owner],card(owner))
                assertEquals(1,rows(owner).size)
                assertFalse(String(LuaValue.encode(result(owner,window)),Charsets.ISO_8859_1).contains(finished.canonicalPath))
                assertEquals(78L,result(owner,battery)["level"])
            }
            events.clear()
            assertEquals(true,model.storageCommand(commandOwner,"storage.refresh",emptyMap<Any,Any>())["ok"])
            for(owner in owners) assertEquals(1,rows(owner).size)
            assertEquals(owners.toSet(),events.map { it["owner"] }.toSet())
            events.clear()
            assertFalse(model.publish("departed",listOf(window)))
            assertFalse(model.refreshLocalFiles("departed"))
            assertTrue(events.isEmpty())
            assertEquals("fixture",store.meta("owner"))
        }
    }
}
