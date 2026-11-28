// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion.server.bookorbit

import net.fledgewing.orbitcompanion.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files

class DeviceLibraryTest {
    @Test fun recentlyAddedUsesPersistedFirstSeenAcrossEditsAndWorkerRestarts() {
        val root=Files.createTempDirectory("recent-device").toFile()
        try {
            val books=File(root,"Books").apply { mkdirs() }
            val cache=File(root,"cache").apply { mkdirs() }
            val old=File(books,"old.epub").apply { writeText("old") }
            fun window(now: Long, query: Map<String,Any?> = emptyMap()) = DeviceLibrary(listOf(books),cache,{now}).project(DeviceLibrary.OWNER,
                mapOf("op" to "window","source" to "recently-added","query" to query,"limit" to 1))
            val original=((window(1000)["items"] as List<*>).single() as Map<*,*>)["added"]
            val new=File(books,"new.epub").apply { writeText("new") }
            old.writeText("edited");old.setLastModified(999999999999L)
            val recent=window(2000)
            assertEquals(2,recent["total"]);assertEquals(1,recent["next"])
            assertEquals(new.canonicalPath,((recent["items"] as List<*>).single() as Map<*,*>)["local_path"])
            val oldest=(window(3000,mapOf("sort" to "added","dir" to "asc"))["items"] as List<*>).single() as Map<*,*>
            assertEquals(original,oldest["added"]);assertEquals(old.canonicalPath,oldest["local_path"])
            assertEquals(1,window(4000,mapOf("q" to "new"))["total"])
        } finally { root.deleteRecursively() }
    }
    @Test fun localReaderAndBookJoinSavedPerBookStatsWithoutInventingCompletion() {
        val root=Files.createTempDirectory("device-book-stats").toFile()
        try {
            val books=File(root,"Books").apply { mkdirs() }
            val book=File(books,"one.epub").apply { writeText("fixture") }
            val md5="a".repeat(32)
            File(books,"one.sdr/metadata.epub.lua").apply { parentFile!!.mkdirs();writeText("return "+String(LuaValue.encode(mapOf("partial_md5_checksum" to md5,"summary" to mapOf("status" to "reading"))),Charsets.ISO_8859_1)) }
            val cache=File(root,"cache").apply { mkdirs() }
            JdbcSql(File(root,"statistics.sqlite3")).use { db ->
                db.exec("CREATE TABLE book(id INTEGER,md5 TEXT)");db.exec("CREATE TABLE page_stat(id_book INTEGER,page INTEGER,start_time INTEGER,duration INTEGER)")
                db.exec("INSERT INTO book VALUES(1,?)",md5)
                db.exec("INSERT INTO page_stat VALUES(1,1,1793534400,60),(1,2,1793534400,120)")
            }
            val noScan=object : File(books.path) {
                override fun listFiles(): Array<File>? = error("A reader panel must not scan the library")
            }
            val direct=DeviceLibrary(listOf(noScan),cache,bookStats={ ReaderBookStats.read(cache,it) { file -> JdbcSql(file) } })
                .project(DeviceLibrary.OWNER,mapOf("op" to "reader","path" to book.canonicalPath))
            assertEquals(2L,(((direct["items"] as List<*>).single() as Map<*,*>)["stats"] as Map<*,*>)["pages_read"])
            val adapter=DeviceLibrary(listOf(books),cache,bookStats={ ReaderBookStats.read(cache,it) { file -> JdbcSql(file) } })
            val row=(adapter.project(DeviceLibrary.OWNER,mapOf("op" to "window","source" to "on-device"))["items"] as List<*>).single() as Map<*,*>
            for(op in listOf("reader","book")) {
                val result=adapter.project(DeviceLibrary.OWNER,mapOf("op" to op,"path" to book.canonicalPath,"key" to row["key"],"native_progress" to .75))
                val info=(result["items"] as List<*>).single() as Map<*,*>
                val stats=info["stats"] as Map<*,*>
                assertEquals(180L,stats["reading_seconds"]);assertEquals(2L,stats["pages_read"])
                assertNull(stats["days_start_to_finish"])
                if(op=="reader") assertEquals(75.0,info["progress"])
            }
        } finally { root.deleteRecursively() }
    }
    @Test fun localPickBackUpRemovesTheLatestReaderBeforeApplyingItsQuery() {
        val root=Files.createTempDirectory("local-pick-back-up").toFile()
        try {
            for(i in 1..3) {
                File(root,"book-$i.epub").writeText("fixture")
                val dir=File(root,"book-$i.sdr").apply { mkdirs() }
                File(dir,"metadata.epub.lua").apply {
                    writeText("return "+String(LuaValue.encode(mapOf("doc_props" to mapOf("title" to "Book $i"),"summary" to mapOf("status" to "reading"))),Charsets.ISO_8859_1))
                    setLastModified(1_700_000_000_000L+i*100_000L)
                }
            }
            val adapter=DeviceLibrary(listOf(root))
            fun window(query:Map<String,Any?> = emptyMap())=adapter.project(DeviceLibrary.OWNER,mapOf("op" to "window","source" to "pick-back-up","query" to query))
            assertEquals(listOf("Book 1","Book 2"),(window()["items"] as List<*>).map { (it as Map<*,*>)["title"] })
            assertEquals(listOf("Book 2"),(window(mapOf("q" to "Book 2"))["items"] as List<*>).map { (it as Map<*,*>)["title"] })
            assertEquals(2,window()["total"])
        } finally { root.deleteRecursively() }
    }
    @Test fun localSeriesAndEndSheetUseTheSameBoundedNeutralRows() {
        val root=Files.createTempDirectory("local-series").toFile()
        try {
            for(i in 1..30) {
                File(root,"book-$i.epub").writeText("fixture")
                val sidecar=File(root,"book-$i.sdr").apply { mkdirs() }
                File(sidecar,"metadata.epub.lua").writeText("return "+String(LuaValue.encode(mapOf(
                    "doc_props" to mapOf("title" to "Book $i","series" to "Fixture series","series_index" to i.toString()),
                    "summary" to mapOf("status" to if(i==1) "reading" else "new"))),Charsets.ISO_8859_1))
            }
            val adapter=DeviceLibrary(listOf(root))
            val sources=adapter.project(DeviceLibrary.OWNER,mapOf("op" to "sources","category" to "series"))
            val source=(sources["items"] as List<*>).single() as Map<*,*>
            assertEquals("series:Fixture series",source["src"]);assertEquals(30,source["count"])
            val window=adapter.project(DeviceLibrary.OWNER,mapOf("op" to "window","source" to mapOf("kind" to "series","key" to "Fixture series"),"limit" to 6))
            assertEquals(30,window["total"]);assertEquals(6,(window["items"] as List<*>).size)
            for(category in listOf("libraries","collections","lists")) assertTrue((adapter.project(DeviceLibrary.OWNER,mapOf("op" to "sources","category" to category))["items"] as List<*>).isEmpty())
            val summary=adapter.project(DeviceLibrary.OWNER,mapOf("op" to "library.summary"))
            assertEquals(1,(summary["browse"] as Map<*,*>)["series"]);assertNull((summary["browse"] as Map<*,*>)["libraries"])
            val series=adapter.project(DeviceLibrary.OWNER,mapOf("op" to "series","key" to "Fixture series","limit" to 6))
            assertEquals(2,(series["items"] as List<*>).size)
            assertEquals(3,series["row_count"])
            assertEquals(24,(series["dots"] as List<*>).size)
            assertEquals("Book 1",((series["items"] as List<*>).first() as Map<*,*>)["title"])
            val finish=adapter.project(DeviceLibrary.OWNER,mapOf("op" to "reader.finish","path" to File(root,"book-1.epub").canonicalPath,"rating" to 4))
            assertEquals("Fixture series",finish["series_key"])
            assertEquals("Book 2",(finish["next"] as Map<*,*>)["title"])
            assertEquals("Next in series · Book 2",LuaValue.utf8((finish["next"] as Map<*,*>)["line"] as String))
            assertEquals(2,finish["row_count"])
            assertEquals(4,finish["stars"])
            assertEquals("missing",adapter.project(DeviceLibrary.OWNER,mapOf("op" to "series","key" to "absent"))["error"])
            assertEquals("unauthorized",adapter.project("other-owner",mapOf("op" to "series","key" to "Fixture series"))["error"])
        } finally { root.deleteRecursively() }
    }
    @Test fun localProjectionsWorkWithoutAdapterOrCatalogOwnershipAndAfterSignOut() {
        val volume=Files.createTempDirectory("device-library").toFile()
        try {
            val folder=File(volume,"Books").apply { mkdirs() }
            val book=File(folder,"fixture.epub").apply { writeText("fixture") }
            val sidecar=File(folder,"fixture.sdr").apply { mkdirs() }
            File(sidecar,"metadata.epub.lua").writeText("return {[\"doc_props\"]={[\"title\"]=\"Local title\"},[\"summary\"]={[\"status\"]=\"reading\"},[\"percent_finished\"]=0.25}")
            val cover=File(sidecar,"cover.jpg").apply { writeText("fixture cover") }
            val cache=File(volume,"koreader/settings/orbit-cache").apply { mkdirs() }
            CacheStore(cache,{}) { JdbcSql(it) }.use { store ->
                // No adapter is available: its methods must never be consulted for device data.
                val unavailable=object : ServerAdapter {
                    override val id="unavailable"
                    override fun project(owner: String,request: Map<*,*>): Map<String,Any?> = error("remote projection")
                    override fun cachedReadingStats(owner: String): RemoteReadingStats? = error("remote stats")
                }
                val model=LibraryReadModel(store,{99},{},readingStats={ mapOf("state" to "ready","total_seconds" to 600) },
                    battery={ mapOf("level" to 75) },accountStats={ error("account stats") },adapter=unavailable)
                fun read(op: String, vararg args: Pair<String,Any?>): Map<*,*> {
                    val request=String(LuaValue.encode(mapOf("op" to op,"limit" to 1,"bytes" to 16384)+args),Charsets.ISO_8859_1)
                    model.publish(DeviceLibrary.OWNER,listOf(request))
                    val body=store.db().query("SELECT body FROM library_views WHERE owner=? AND request=?",DeviceLibrary.OWNER,request) { it.bytes(0)!! }.single()
                    assertTrue(body.size<=16384)
                    return LuaValue.parse(body) as Map<*,*>
                }
                for(previousOwner in listOf<String?>(null,"previous-account")) {
                    if(previousOwner!=null) store.own(previousOwner)
                    val data=read("window","source" to "on-device")
                    val row=(data["items"] as List<*>).single() as Map<*,*>
                    assertEquals("Local title",row["title"]); assertEquals(book.canonicalPath,row["local_path"])
                    assertEquals(25.0,(row["progress"] as Number).toDouble(),0.001)
                    val reader=(read("reader","path" to book.canonicalPath,"native_progress" to 0.75)["items"] as List<*>).single() as Map<*,*>
                    assertEquals(75.0,(reader["progress"] as Number).toDouble(),0.001)
                    assertEquals("local-reader",reader["progress_origin"])
                    assertEquals(cover.path,read("cover","key" to row["key"])["local_path"])
                    assertEquals(true,read("capabilities")["onDevice"])
                    assertEquals(false,read("capabilities")["download"])
                    assertEquals(75L,read("battery")["level"])
                    assertFalse(read("reading.stats").containsKey("error"))
                    assertEquals(previousOwner,store.meta("owner"))
                    assertFalse(model.publish("wrong-account",listOf("{op=\"battery\"}")))
                }
                val request=String(LuaValue.encode(mapOf("op" to "battery","limit" to 1,"bytes" to 256)),Charsets.ISO_8859_1)
                LibraryReadModel(store,{99},{},battery={ mapOf("oversized" to "x".repeat(17000)) },adapter=unavailable).publish(DeviceLibrary.OWNER,listOf(request))
                val result=store.db().query("SELECT body FROM library_views WHERE owner=? AND request=?",DeviceLibrary.OWNER,request) { LuaValue.parse(it.bytes(0)!!) as Map<*,*> }.single()
                assertEquals("budget",result["error"])
            }
        } finally { volume.deleteRecursively() }
    }
    @Test fun windowsAreBoundedFilteredAndDoNotFollowEscapingLinks() {
        val root=Files.createTempDirectory("device-window").toFile()
        val outside=Files.createTempDirectory("outside-device").toFile()
        try {
            for(i in 1..30) File(root,"Book $i.epub").writeText("fixture")
            File(outside,"Private.epub").writeText("fixture")
            Files.createSymbolicLink(File(root,"escape").toPath(),outside.toPath())
            val adapter=DeviceLibrary(listOf(root))
            val page=adapter.project(DeviceLibrary.OWNER,mapOf("op" to "window","source" to "on-device","limit" to 6,"query" to mapOf("sort" to "title")))
            assertEquals(6,(page["items"] as List<*>).size); assertEquals(30,page["total"])
            val search=adapter.project(DeviceLibrary.OWNER,mapOf("op" to "window","source" to "on-device","query" to mapOf("q" to "Book 20")))
            assertEquals(1,(search["items"] as List<*>).size)
            assertEquals("unauthorized",adapter.project("other",mapOf("op" to "window"))["error"])
        } finally { root.deleteRecursively(); outside.deleteRecursively() }
    }
    @Test fun readerSeriesCountComesFromTheLastCatalogSnapshotWithoutRescanning() {
        val root=Files.createTempDirectory("reader-series").toFile()
        try {
            val cache=File(root,"cache").apply { mkdirs() };val books=File(root,"Books").apply { mkdirs() }
            for(i in 1..5) {
                File(books,"$i.epub").writeText("fixture")
                File(books,"$i.sdr/metadata.epub.lua").apply { parentFile!!.mkdirs();writeText("return "+String(LuaValue.encode(mapOf("doc_props" to mapOf("series" to "Tidewright","series_index" to i))),Charsets.ISO_8859_1)) }
            }
            DeviceLibrary(listOf(books),cache).personalCatalog(DeviceLibrary.OWNER)
            val noScan=object:File(books.path) { override fun listFiles():Array<File>? = error("reader must not scan") }
            val result=DeviceLibrary(listOf(noScan),cache).project(DeviceLibrary.OWNER,mapOf("op" to "reader","path" to File(books,"2.epub").path))
            val row=(result["items"] as List<*>).single() as Map<*,*>
            assertEquals(5,row["series_total"]);assertEquals(2L,row["series_position"])
        } finally { root.deleteRecursively() }
    }

}
