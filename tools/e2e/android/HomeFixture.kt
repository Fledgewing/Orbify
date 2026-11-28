// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

import android.os.Environment
import java.io.File

/** Opt-in synthetic Home data, compiled only by the external emulator builder. */
internal object HomeFixture {
    private val marker get()=File(Environment.getExternalStorageDirectory(),"Books/.booksync-home-fixture")
    fun project(books: DeviceLibrary,request:Map<*,*>):Map<String,Any?>? {
        if(!marker.isFile) return null
        val fresh=mapOf("saved" to true,"origin" to "emulator-fixture")
        if(request["op"]=="capabilities") return books.capabilities(DeviceLibrary.OWNER)+mapOf("wantToRead" to true,"onDevice" to true,"lists" to mapOf("read" to true,"save" to false),"retainedFinishedYears" to true,"retainedSeriesNext" to true,"series" to mapOf("read" to true,"downloadNext" to true))
        if(request["op"]=="lists") return mapOf("items" to listOf(
            mapOf("key" to "fixture-list","title" to "Short reads","count" to 84),
            mapOf("key" to "fixture-scifi","title" to "Unread science fiction","count" to 132),
            mapOf("key" to "fixture-month","title" to "Added this month","count" to 23),
            mapOf("key" to "fixture-series","title" to "Series to continue","count" to 17)),"total" to 9,"freshness" to fresh)
        if(request["op"]!="window") return null
        val source=request["source"]
        val localRequest=if(source in listOf("recently-added","want-to-read")) request.toMutableMap().also { it["source"]="all" } else request
        val result=books.project(DeviceLibrary.OWNER,localRequest)
        val rows=(result["items"] as? List<*>).orEmpty().mapIndexed { index,value ->
            val row=value as? Map<*,*> ?: emptyMap<Any,Any>()
            val number=(row["series_position"] as? Number)?.toInt()
            val added=java.time.LocalDate.now().minusDays(index.toLong()).toString()
            row.entries.associate { it.key.toString() to it.value }+mapOf(
                "series_line" to (row["series_key"]?.let { "$it · Book ${number ?: 1}" }),
                "time_left" to listOf("3 h 22 m left","4 h 37 m left","2 h 1 m left")[index%3],
                "finish_forecast" to "Done by Saturday","last_read_label" to "Read ${index+2} days ago","added" to added,
                "added_label" to when(index) { 0 -> "Today"; 1 -> "Yesterday"; else -> "$index days ago" })
        }
        return result+mapOf("items" to rows,"freshness" to fresh)
    }
}
