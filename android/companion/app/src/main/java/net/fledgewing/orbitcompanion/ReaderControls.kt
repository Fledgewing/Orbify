// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

/** Native reader scalars arrive bounded; all marker normalization and labels run on the worker. */
object ReaderControls {
    fun project(native: Map<*, *>, forecast: Map<String,Any?> = emptyMap()): Map<String, Any?> {
        fun number(value: Any?) = (value as? Number)?.toDouble()?.takeIf { it.isFinite() }
        val total = number(native["total"])?.toInt()?.takeIf { it > 0 }
        val page = number(native["page"])?.toInt()?.takeIf { total != null && it in 1..total }
        fun markers(key: String): List<Double> = if (total == null) emptyList() else
            (native[key] as? List<*>)?.take(64)?.mapNotNull { number(it)?.takeIf { n -> n in 1.0..total.toDouble() } }
                ?.distinct()?.sorted()?.map { it / total } ?: emptyList()
        val chapters = markers("chapters")
        val fraction = if (page != null && total != null) page.toDouble()/total else null
        val chapterTotal = number(native["chapter_total"])?.toInt()?.takeIf { it > 0 } ?: chapters.size
        val chapter = number(native["chapter_index"])?.toInt()?.takeIf { it in 1..chapterTotal }
            ?: fraction?.let { f -> if (chapterTotal <= 64) chapters.count { it <= f }.coerceAtLeast(1) else null }
        val title = (native["chapter_title"] as? String)?.take(256)?.takeIf { it.isNotBlank() }
        val pace=number(forecast["seconds_per_fraction"])?.takeIf { it>0 }
        val next=number(native["next_page"])?.takeIf { page!=null && total!=null && it>page && it<=total }
            ?: total?.toDouble()?.takeIf { chapter!=null && chapter==chapterTotal }
        fun remaining(distance:Double?,suffix:String):String? = if(distance==null || pace==null || total==null) null else {
            val minutes=kotlin.math.ceil(distance/total*pace/60).toLong()
            LuaValue.str((if(minutes>=60) "${minutes/60} h ${minutes%60} m" else "$minutes m")+" left in $suffix")
        }
        return mapOf("items" to listOf(mapOf("progress" to fraction,
            "time_left" to remaining(if(page!=null && total!=null) (total-page).toDouble() else null,"book"),
            "chapter_time_left" to remaining(if(page!=null && next!=null) next-page else null,"chapter"),
            "position" to if (page != null) LuaValue.str("p. $page of $total · ${(fraction!!*100+.5).toInt()}%") else "Position not available yet",
            "chapter" to if (chapter != null && chapters.isNotEmpty()) "Chapter $chapter of $chapterTotal" else "Chapters not available yet",
            "chapter_title" to title?.let { LuaValue.str("$chapter · ${LuaValue.utf8(it)}") },
            "markers_reduced" to (chapterTotal > 64), "chapters" to chapters, "bookmarks" to markers("bookmarks"), "marked" to (native["marked"] == true))))
    }
    fun read(native:Map<*,*>,file:java.io.File,now:Long,open:(java.io.File)->Sql={AndroidSql(it,readOnly=true)}):Map<String,Any?> {
        val md5=(native["md5"] as? String)?.takeIf { Regex("[0-9a-f]{32}").matches(it) }
        val page=(native["page"] as? Number)?.toDouble()
        val total=(native["total"] as? Number)?.toDouble()?.takeIf { it>0 }
        val forecast=if(md5!=null && page!=null && total!=null && file.isFile) runCatching {
            open(file).use { ReadingStats.forecast(it,md5,page/total,now,0,includePace=true) }
        }.getOrElse { if(it is InterruptedException) throw it;emptyMap() } else emptyMap()
        return project(native,forecast)
    }

}
