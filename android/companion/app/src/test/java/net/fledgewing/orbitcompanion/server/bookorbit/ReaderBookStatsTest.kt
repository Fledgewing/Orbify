// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion.server.bookorbit

import net.fledgewing.orbitcompanion.*

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files

class ReaderBookStatsTest {
    @Test fun workerAggregatesSavedStatsAndUsesTheActualCompletionDay() {
        val dir=Files.createTempDirectory("reader-stats").toFile()
        try {
            val root=File(dir,"orbit-cache").apply { mkdirs() }
            val md5="a".repeat(32)
            val file=File(dir,"fixture.epub").apply { writeText("fixture") }
            val sidecar=File(dir,"fixture.sdr/metadata.epub.lua").apply { parentFile?.mkdirs() }
            val summary=mapOf("summary" to mapOf("status" to "complete","modified" to "2026-11-03"))
            sidecar.writeText("-- fixture\nreturn "+String(LuaValue.encode(summary),Charsets.ISO_8859_1)+"\n")
            val entry=mapOf("md5" to md5,"path" to file.path)
            val stats=File(dir,"statistics.sqlite3")
            JdbcSql(stats).use { db ->
                db.exec("CREATE TABLE book(id INTEGER,md5 TEXT)")
                db.exec("CREATE TABLE page_stat(id_book INTEGER,page INTEGER,start_time INTEGER,duration INTEGER)")
                db.exec("INSERT INTO book VALUES(1,?)",md5)
                // Midday UTC is on the same date in the CI/local zones.
                db.exec("INSERT INTO page_stat VALUES(1,1,1793534400,60),(1,1,1793534400,120),(1,2,1793534400,180)")
                db.exec("INSERT INTO book VALUES(2,'other')")
                db.exec("INSERT INTO page_stat VALUES(2,1,1793534400,9999)")
            }
            val result=ReaderBookStats.read(root,entry,now=1794312000) { JdbcSql(it) }
            assertEquals(true,result["available"])
            assertEquals(2L,result["pages_read"])
            assertEquals(360L,result["reading_seconds"])
            assertEquals(9L,result["started_days"])
            assertEquals(3L,result["days_start_to_finish"])
            sidecar.writeText("-- fixture\nreturn "+String(LuaValue.encode(mapOf("summary" to mapOf("status" to "reading","modified" to "2026-11-03"))),Charsets.ISO_8859_1))
            assertNull(ReaderBookStats.read(root,entry) { JdbcSql(it) }["days_start_to_finish"])
            assertEquals(false,ReaderBookStats.read(root,mapOf("md5" to "b".repeat(32))) { JdbcSql(it) }["available"])
            assertEquals(false,ReaderBookStats.read(root,mapOf("md5" to "invalid"))["available"])
        } finally { dir.deleteRecursively() }
    }
    @Test fun readerProjectionResolvesOnlyThisOwnersLedgerAndLeavesBatteryUnknown() {
        val dir=Files.createTempDirectory("reader-projection").toFile()
        try {
            CacheStore(dir,{}) { JdbcSql(it) }.use { st ->
                val owner="fixture|https://library.invalid"; st.own(owner)
                st.putItem(mapOf("id" to 7L,"title" to "The Moon","progressPercentage" to 62L),1)
                val ledger=File(dir,"copies/ask.lua").apply { parentFile?.mkdirs() }
                ledger.writeBytes(LuaValue.encode(mapOf("owner" to owner,"books" to listOf(mapOf("book_id" to 7,"path" to "/books/fixture.epub")))))
                fun read(args: Map<String,Any?>): Map<*,*> {
                    val request=String(LuaValue.encode(args),Charsets.ISO_8859_1)
                    LibraryReadModel(st,{99},{}).publish(owner,listOf(request))
                    return st.db().query("SELECT body FROM library_views WHERE owner=? AND request=?",owner,request) { LuaValue.parse(it.bytes(0)!!) as Map<*,*> }.single()
                }
                val book=(read(mapOf("op" to "reader","path" to "/books/fixture.epub"))["items"] as List<*>).single() as Map<*,*>
                assertEquals(BookOrbitLibrary.key(owner,"book",7),book["key"])
                assertEquals(62L,book["progress"])
                val current=(read(mapOf("op" to "reader","path" to "/books/fixture.epub","native_progress" to 0.8))["items"] as List<*>).single() as Map<*,*>
                assertEquals(80L,current["progress"])
                assertEquals("local-reader",current["progress_origin"])
                val invalid=(read(mapOf("op" to "reader","path" to "/books/fixture.epub","native_progress" to 1.2))["items"] as List<*>).single() as Map<*,*>
                assertEquals(62L,invalid["progress"])
                assertEquals(62L,(st.bookItem(7) as Map<*,*>)["progressPercentage"])

                assertEquals(false,(book["stats"] as Map<*,*>)["available"])
                val battery=read(mapOf("op" to "battery"))
                assertNull(battery["hours_usual_use"])
                assertEquals("local-device",(battery["freshness"] as Map<*,*>)["origin"])
                assertTrue((read(mapOf("op" to "reader","path" to "/books/other.epub"))["items"] as List<*>).isEmpty())
                ledger.writeBytes(LuaValue.encode(mapOf("owner" to "other","books" to listOf(mapOf("book_id" to 7,"path" to "/books/fixture.epub")))))
                assertTrue((read(mapOf("op" to "reader","path" to "/books/fixture.epub"))["items"] as List<*>).isEmpty())
            }
        } finally { dir.deleteRecursively() }
    }
}
