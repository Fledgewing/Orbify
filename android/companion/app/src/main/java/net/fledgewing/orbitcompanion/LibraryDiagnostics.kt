// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.io.File
import java.util.concurrent.Executors

/** Neutral, local-only Library service. One row / 8 KiB; no server, catalog, scan or subprocess. */
object LibraryDiagnostics {
    data class Snapshot(val text: String, val canClear: Boolean, val rows: Int = 1, val setup: List<Pair<String, String>> = emptyList()) {
        val bytes: Int get() = text.toByteArray(Charsets.UTF_8).size
    }
    private val queue = Executors.newSingleThreadExecutor { r -> Thread(r, "booksync-diagnostics").apply { isDaemon = true } }
    private val main by lazy { Handler(Looper.getMainLooper()) }
    private var summary: CrashSummary? = null
    private var summaryFile: File? = null
    @Synchronized internal fun store(ctx: Context): CrashSummary {
        val file = File(ctx.applicationContext.noBackupFilesDir, "companion-crashes.bin")
        if (summaryFile != file) {
            summary = CrashSummary(file)
            summaryFile = file
        }
        return requireNotNull(summary)
    }

    internal fun project(saved: CrashSummary.Snapshot): Snapshot = Snapshot(saved.text(), !saved.available || saved.entries.isNotEmpty()).also {
        check(it.rows == 1 && it.bytes <= CrashSummary.MAX_BYTES)
    }
    internal fun readerCrash(file: File): String = try {
        if (!file.exists()) "" else file.inputStream().use { input ->
            val bytes = ByteArray(4097)
            var size = 0
            while (size < bytes.size) {
                val n = input.read(bytes, size, bytes.size-size)
                if (n < 0) break
                size += n
            }
            if (size > 4096) "KOReader crash reason unavailable" else
                String(bytes, 0, size, Charsets.UTF_8).takeIf { it.startsWith("KOReader Lua main loop\n") && it.toByteArray(Charsets.UTF_8).size <= 4096 }
                    ?: "KOReader crash reason unavailable"
        }
    } catch (_: Exception) { "KOReader crash reason unavailable" }
    private fun readerCrashFile() = File(android.os.Environment.getExternalStorageDirectory(),
        "koreader/settings/orbit-cache/koreader-crash.txt")
    internal fun withReaderCrash(snapshot: Snapshot, text: String): Snapshot {
        if (text.isEmpty()) return snapshot
        val combined = snapshot.text.take(800) + "\n\n" + text + "\nSaved on this reader. Never sent automatically."
        return snapshot.copy(text = combined, canClear = true).also { check(it.bytes <= CrashSummary.MAX_BYTES) }
    }
    // Existing setup diagnostics remain unchanged, accessed through the same Library surface.
    fun snapshot(ctx: Context, done: (Snapshot) -> Unit) {
        val app = ctx.applicationContext
        queue.execute {
            val start = System.nanoTime()
            val crashes = runCatching { withReaderCrash(project(store(app).snapshot()), readerCrash(readerCrashFile())) }.getOrElse { Snapshot("Crash summary unavailable", true) }
            val setup = runCatching { Setup.details(app) }.getOrElse { listOf("Setup diagnostics" to "Unavailable") }
            val setupBytes = setup.sumOf { (k,v) -> k.toByteArray().size + v.toByteArray().size }
            val snapshot = crashes.copy(setup = if (setupBytes <= 8192) setup else listOf("Setup diagnostics" to "Unavailable"))
            OLog.i("library.diagnostics rows=1 bytes=${snapshot.bytes} ms=${(System.nanoTime()-start)/1_000_000}")
            main.post { done(snapshot) }
        }
    }
    internal fun clearRecords(store: CrashSummary, reader: File): Boolean {
        val cleared = store.clear()
        return cleared && (!reader.exists() || reader.delete())
    }
    /** Explicit command; never clears any other diagnostics or user data. */
    fun clear(ctx: Context, done: (Boolean) -> Unit) {
        val app = ctx.applicationContext
        queue.execute { val ok = runCatching { clearRecords(store(app),readerCrashFile()) }.getOrDefault(false); main.post { done(ok) } }
    }
}
