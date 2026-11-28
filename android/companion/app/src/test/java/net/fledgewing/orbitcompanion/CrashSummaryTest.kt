// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.time.ZoneId

class CrashSummaryTest {
    private fun file() = File(Files.createTempDirectory("booksync-crash-test").toFile().apply { deleteOnExit() }, "summary")
    private fun crash(message: String = "private") = IllegalStateException(message).apply {
        stackTrace = arrayOf(StackTraceElement("net.fledgewing.orbitcompanion.Worker", "run", "/private/book.epub", 42))
    }
    @Test fun readerLuaReasonIsBoundedAndIncludedInCrashSummary() {
        val f = file()
        assertEquals("", LibraryDiagnostics.readerCrash(f))
        val trace = "KOReader Lua main loop\nfixture error\nstack traceback:\nko/home_host.lua:42"
        f.writeText(trace)
        assertEquals(trace, LibraryDiagnostics.readerCrash(f))
        val projected = LibraryDiagnostics.withReaderCrash(LibraryDiagnostics.project(CrashSummary(file()).snapshot()), trace)
        assertTrue(projected.text.contains("fixture error")); assertTrue(projected.canClear)
        assertTrue(projected.bytes <= CrashSummary.MAX_BYTES)
        val store = CrashSummary(file())
        store.record(crash(), "0.12.1")
        assertTrue(LibraryDiagnostics.clearRecords(store, f)); assertFalse(f.exists())
        assertTrue(store.snapshot().entries.isEmpty())
        f.writeBytes(ByteArray(4097))
        assertEquals("KOReader crash reason unavailable", LibraryDiagnostics.readerCrash(f))
        f.writeText("not a crash record")
        assertEquals("KOReader crash reason unavailable", LibraryDiagnostics.readerCrash(f))
    }
    @Test fun duplicateSurvivesRestartAndVersionSeparates() {
        val f = file(); val first = CrashSummary(f) { 1000 }
        first.record(crash(), "0.12.0-preview.1")
        CrashSummary(f) { 2000 }.record(crash("different secret"), "0.12.0-preview.1")
        var entries = CrashSummary(f).snapshot().entries
        assertEquals(1, entries.size); assertEquals(2, entries[0].count)
        assertEquals(1000L, entries[0].first); assertEquals(2000L, entries[0].last)
        first.record(crash(), "0.12.0-preview.2")
        entries = first.snapshot().entries
        assertEquals(2, entries.size)
    }
    @Test fun fingerprintSeparatesTypeAndFrames() {
        val s = CrashSummary(file())
        s.record(crash(), "0.12.0")
        s.record(IllegalArgumentException(), "0.12.0")
        s.record(crash().apply { stackTrace = emptyArray() }, "0.12.0")
        assertEquals(3, s.snapshot().entries.size)
    }
    @Test fun tornAndOversizedRecordsAreUnavailableAndRecover() {
        val f = file(); val s = CrashSummary(f)
        for (bytes in listOf(byteArrayOf(1,2,3), ByteArray(8193))) {
            f.writeBytes(bytes); assertFalse(s.snapshot().available)
            s.record(crash(), "0.12.0"); assertTrue(s.snapshot().available)
        }
    }
    @Test fun boundedToFourFingerprintsAndEightFramesAndEightKiB() {
        val f = file(); val s = CrashSummary(f)
        for (i in 1..10) s.record(crash().apply { stackTrace = Array(10000) { stackTrace[0] } }, "0.12.$i")
        val entries = s.snapshot().entries
        assertEquals(4, entries.size); assertEquals("0.12.7", entries.first().version)
        assertTrue(entries.all { it.frames.size == 8 }); assertTrue(f.length() <= 8192)
        assertTrue(LibraryDiagnostics.project(s.snapshot()).bytes <= 8192)
        assertEquals(1, LibraryDiagnostics.project(s.snapshot()).rows)
    }
    @Test fun onlyExactAllowlistedSymbolsAndTypesReachDiskOrCopy() {
        val f = file(); val s = CrashSummary(f)
        val error = object : RuntimeException("password title https://secret.example account") {}.apply {
            stackTrace = arrayOf(
                StackTraceElement("net.fledgewing.orbitcompanion.Worker", "run", "/private/title.epub", 21),
                StackTraceElement("net.fledgewing.orbitcompanion.Worker", "password", "secret", 1),
                StackTraceElement("evil.Worker", "run", "secret", 1),
                StackTraceElement("net.fledgewing.orbitcompanion.SecretAccount", "run", "secret", 1))
        }
        s.record(error, "0.12.0")
        val e = s.snapshot().entries.single()
        assertEquals("Throwable", e.type); assertEquals(listOf("Worker.run"), e.frames)
        val copied = SetupDetails.copyText("0.12.0", listOf("Companion crashes" to s.snapshot().text()))
        for (secret in listOf("password", "title", "https://", "account", "/private", "SecretAccount", "evil")) {
            assertFalse(f.readText(Charsets.ISO_8859_1).contains(secret)); assertFalse(copied.contains(secret))
        }
    }
    @Test fun invalidVersionCannotPersistFreeText() {
        val s = CrashSummary(file()); s.record(crash(), "password /private")
        assertEquals("0.0.0", s.snapshot().entries.single().version)
    }
    @Test fun rollbackKeepsOrderedTimeRangeAndLocalTimeIsRendered() {
        val f = file()
        CrashSummary(f) { 2000 }.record(crash(), "0.12.0")
        val s = CrashSummary(f) { 1000 }; s.record(crash(), "0.12.0")
        assertEquals(1000L, s.snapshot().entries.single().first)
        assertEquals(2000L, s.snapshot().entries.single().last)
        assertTrue(s.snapshot().text(ZoneId.of("America/Los_Angeles")).contains("31 Dec 1969, 16:00 PST"))
    }
    @Test fun extremeClockValuesAreBounded() {
        val f = file(); CrashSummary(f) { Long.MAX_VALUE }.record(crash(), "0.12.0")
        CrashSummary(f) { Long.MIN_VALUE }.record(crash(), "0.12.0")
        assertTrue(CrashSummary(f).snapshot().available)
        assertTrue(CrashSummary(f).snapshot().text().isNotEmpty())
    }
    @Test fun exactlyOnceDelegationWithOriginalThreadAndThrowableEvenWhenSaveFails() {
        for (fail in listOf(false,true)) {
            var calls = 0; var saves = 0; val error = crash(); val thread = Thread.currentThread()
            val h = CrashSummaryHandler({ saves++; if (fail) throw OutOfMemoryError() }, { t,e ->
                calls++; assertSame(thread,t); assertSame(error,e)
            })
            h.uncaughtException(thread,error); assertEquals(1,saves); assertEquals(1,calls)
        }
    }
    @Test fun previousHandlerFailureIsNotDelegatedAgain() {
        var calls = 0
        val h = CrashSummaryHandler({}, { _,_ -> calls++; throw IOException() })
        try { h.uncaughtException(Thread.currentThread(), crash()); fail() } catch (_: IOException) { }
        assertEquals(1,calls)
    }
    @Test fun realWriteFailureStillDelegatesAndRetainsPriorRecord() {
        val f = file(); val s = CrashSummary(f); s.record(crash(), "0.12.0")
        val old = f.readBytes(); File(f.parentFile, f.name + ".part").mkdir()
        var calls = 0
        CrashSummaryHandler({ s.record(it,"0.12.1") }, { _,_ -> calls++ }).uncaughtException(Thread.currentThread(), crash())
        assertEquals(1,calls); assertArrayEquals(old,f.readBytes())
    }
    @Test fun counterSaturatesInsteadOfOverflowing() {
        val f = file(); val s = CrashSummary(f); s.record(crash(),"0.12.0")
        val bytes = f.readBytes()
        java.nio.ByteBuffer.wrap(bytes,bytes.size-4,4).putInt(CrashSummary.MAX_COUNT)
        f.writeBytes(bytes); s.record(crash(),"0.12.0")
        assertEquals(CrashSummary.MAX_COUNT,s.snapshot().entries.single().count)
    }
    @Test fun untrustedStoredSymbolsAreRejectedBeforePresentation() {
        val f = file(); val s = CrashSummary(f); s.record(crash(),"0.12.0")
        val bytes = f.readBytes()
        val symbol = "Worker.run".toByteArray()
        val at = bytes.indices.first { i -> i+symbol.size<=bytes.size && bytes.copyOfRange(i,i+symbol.size).contentEquals(symbol) }
        "Secret.run".toByteArray().copyInto(bytes,at)
        f.writeBytes(bytes)
        assertFalse(s.snapshot().available)
        assertFalse(LibraryDiagnostics.project(s.snapshot()).text.contains("Secret"))
    }
    @Test fun clearOnlyDeletesCrashFilesAndEmptySurvivesRestart() {
        val f = file(); val sentinel = File(f.parentFile,"reading-data").apply { writeText("unchanged") }
        val s = CrashSummary(f); s.record(crash(),"0.12.0")
        File(f.parentFile,f.name+".part").writeText("torn")
        assertTrue(s.clear()); assertTrue(CrashSummary(f).snapshot().entries.isEmpty())
        assertEquals("unchanged",sentinel.readText())
        assertEquals("No companion crash summaries saved.",s.snapshot().text())
    }
}
