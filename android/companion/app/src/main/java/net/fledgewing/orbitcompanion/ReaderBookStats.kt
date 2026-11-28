// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

import java.io.File
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/** Borrow KOReader's existing statistics read-only, on the companion worker. Never flush the reader. */
object ReaderBookStats {
    fun read(root: File, entry: Map<*, *>?, now: Long = System.currentTimeMillis()/1000, open: (File) -> Sql = { AndroidSql(it, readOnly = true) }): Map<String, Any?> {
        val missing = mapOf("available" to false)
        val md5 = (entry?.get("md5") as? String)?.takeIf { Regex("[0-9a-f]{32}").matches(it) } ?: return missing
        val stats = File(root.parentFile, "statistics.sqlite3")
        if (!stats.isFile) return missing
        return runCatching {
            open(stats).use { db ->
                db.query("""SELECT COUNT(DISTINCT p.page), SUM(MAX(0,p.duration)),
                    date(MIN(p.start_time),'unixepoch','localtime')
                    FROM page_stat p JOIN book b ON b.id=p.id_book WHERE b.md5=?""", md5) {
                    val first = it.text(2)
                    val finished = finishDay(entry)
                    val days = if (first != null && finished != null) runCatching {
                        ChronoUnit.DAYS.between(LocalDate.parse(first), LocalDate.parse(finished)).takeIf { n -> n >= 0 }?.plus(1)
                    }.getOrNull() else null
                    if (first == null) missing else mapOf("available" to true, "pages_read" to it.long(0), "reading_seconds" to it.long(1),
                        "days_start_to_finish" to days,
                        "started_days" to ChronoUnit.DAYS.between(LocalDate.parse(first),
                            java.time.Instant.ofEpochSecond(now).atZone(java.time.ZoneId.systemDefault()).toLocalDate()).takeIf { n -> n>=0 })
                }.single()
            }
        }.getOrDefault(missing)
    }
    private fun finishDay(entry: Map<*, *>?): String? {
        val path = (entry?.get("path") as? String)?.let(LuaValue::utf8) ?: return null
        val book = File(path)
        val sidecar = File(book.parentFile, "${book.nameWithoutExtension}.sdr/metadata.${book.extension}.lua")
        if (!sidecar.isFile || sidecar.length() > 1024 * 1024) return null
        // KOReader util.writeToFile(..., lua_dofile_ready=true): one comment + return.
        val literal = sidecar.readText().replaceFirst(Regex("\\A(?:--[^\\n]*\\n)?\\s*return\\s+"), "")
        val data = LuaValue.parse(literal.toByteArray(Charsets.UTF_8)) as? Map<*, *> ?: return null
        val summary = data["summary"] as? Map<*, *> ?: return null
        return (summary["modified"] as? String)?.takeIf { summary["status"] == "complete" }
    }
}
