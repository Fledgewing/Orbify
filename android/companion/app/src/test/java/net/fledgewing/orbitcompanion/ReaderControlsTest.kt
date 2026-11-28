// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files
import java.io.File

class ReaderControlsTest {
    private fun row(native: Map<String, Any?>): Map<*, *> =
        (ReaderControls.project(native)["items"] as List<*>).single() as Map<*, *>
    @Test fun workerPublishesControlsWithoutCallingTheServerAdapter() {
        val directory=Files.createTempDirectory("reader-controls").toFile()
        try {
            JdbcSql(File(directory,"projection.sqlite3")).use { sql ->
                val owner="fixture|https://library.invalid"
                LibraryReadModel.initialize(sql)
                val store=object: ProjectionStore {
                    override val root=directory
                    override fun db()=sql
                    override fun meta(k: String)=if (k=="owner") owner else null
                    override fun <T> transaction(block: () -> T): T=sql.transaction(block)
                    override fun close()=Unit
                }
                val adapter=object: ServerAdapter {
                    override val id="fixture"
                    override fun project(owner: String,request: Map<*, *>): Map<String, Any?> =
                        error("native controls must not call a server adapter")
                }
                val request=String(LuaValue.encode(mapOf("op" to "reader.controls","limit" to 1,"bytes" to 16384,
                    "native" to mapOf("page" to 50,"total" to 200,"chapters" to listOf(1,100),"marked" to true))),Charsets.ISO_8859_1)
                assertTrue(LibraryReadModel(store,{99},{},adapter=adapter).publish(owner,listOf(request)))
                val snapshot=store.db().query("SELECT body FROM library_views WHERE owner=? AND request=?",owner,request) {
                    LuaValue.parse(it.bytes(0)!!) as Map<*, *>
                }.single()
                val item=(snapshot["items"] as List<*>).single() as Map<*, *>
                assertEquals(LuaValue.str("p. 50 of 200 · 25%"),item["position"])
                assertEquals(true,item["marked"])
                assertFalse(LibraryReadModel(store,{99},{},adapter=adapter).publish("another-owner",listOf(request)))
            }
        } finally { directory.deleteRecursively() }
    }
    @Test fun missingAndInvalidPositionsStayUnknown() {
        for (native in listOf(emptyMap(), mapOf("page" to 1, "total" to 0),
            mapOf("page" to Double.NaN,"total" to 200),mapOf("page" to 201,"total" to 200))) {
            val item=row(native)
            assertNull(item["progress"])
            assertEquals("Position not available yet",item["position"])
            assertEquals(emptyList<Double>(),item["bookmarks"])
        }
    }
    @Test fun workerProjectsDistinctSortedMarkersAndDisplayLabels() {
        val item=row(mapOf("page" to 50,"total" to 200,"marked" to true,
            "chapters" to listOf(1,100,50,50,-1,201,Double.POSITIVE_INFINITY),"bookmarks" to listOf(200,1)))
        assertEquals(.25,item["progress"])
        assertEquals(LuaValue.str("p. 50 of 200 · 25%"),item["position"])
        assertEquals("Chapter 2 of 3",item["chapter"])
        assertEquals(listOf(.005,.25,.5),item["chapters"])
        assertEquals(listOf(.005,1.0),item["bookmarks"])
        assertEquals(true,item["marked"])
    }
    @Test fun pagePercentagesUseTheSameHalfUpRoundingAsTheReaderHeader() {
        assertEquals(LuaValue.str("p. 1 of 200 · 1%"),row(mapOf("page" to 1,"total" to 200))["position"])
        assertEquals(LuaValue.str("p. 199 of 200 · 100%"),row(mapOf("page" to 199,"total" to 200))["position"])
        assertEquals(LuaValue.str("p. 1 of 300 · 0%"),row(mapOf("page" to 1,"total" to 300))["position"])
    }
    @Test fun nativeChapterIdentityDoesNotBecomeTheSampleCount() {
        val item=row(mapOf("page" to 8000,"total" to 10000,"chapters" to (1..64).toList(),
            "chapter_total" to 1000,"chapter_index" to 800,"chapter_title" to "A chapter"))
        assertEquals("Chapter 800 of 1000",item["chapter"])
        assertEquals(LuaValue.str("800 · A chapter"),item["chapter_title"])
        assertEquals(true,item["markers_reduced"])
    }
    @Test fun markerWindowsAndEncodedSnapshotStayBounded() {
        val native=mapOf("page" to 100,"total" to 10000,"chapters" to (1..10000).toList(),"bookmarks" to (1..10000).toList())
        val item=row(native)
        assertEquals(64,(item["chapters"] as List<*>).size)
        assertEquals(64,(item["bookmarks"] as List<*>).size)
        assertTrue(LuaValue.encode(ReaderControls.project(native)).size<=16384)
    }
    @Test fun labelsRoundTripThroughTheUtf8ByteModelExactlyOnce() {
        val item=row(mapOf("page" to 12,"total" to 20,"chapter_total" to 4,"chapter_index" to 3,
            "chapter_title" to LuaValue.str("Lumière · 海"),"chapters" to listOf(1,5,10,15)))
        val encoded=LuaValue.encode(item)
        val parsed=LuaValue.parse(encoded) as Map<*, *>
        assertEquals("3 · Lumière · 海",LuaValue.utf8(parsed["chapter_title"] as String))
        assertEquals("p. 12 of 20 · 60%",LuaValue.utf8(parsed["position"] as String))
    }

    @Test fun measuredPacePopulatesBothReaderPanelsWithoutInventingMissingPace() {
        val native=mapOf("page" to 211,"total" to 341,"next_page" to 228,"chapter_index" to 14,"chapter_total" to 22)
        val item=(ReaderControls.project(native,mapOf("seconds_per_fraction" to 31700.0))["items"] as List<*>).single() as Map<*,*>
        assertEquals("3 h 22 m left in book",LuaValue.utf8(item["time_left"] as String))
        assertEquals("27 m left in chapter",LuaValue.utf8(item["chapter_time_left"] as String))
        assertNull(row(native)["time_left"]);assertNull(row(native)["chapter_time_left"])
    }

}
