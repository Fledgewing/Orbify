package net.fledgewing.orbitcompanion

import android.os.Process
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class BulkWorkTest {
    @Test fun everyRootAndNewSubfolderGetsAnIdempotentNoMediaMarker() {
        val root = Files.createTempDirectory("bulk").toFile()
        try {
            val dirs = listOf(File(root, "koreader/cache/bookorbit"), File(root, "orbit-cache"), File(root, "orbit-sleep"))
            NoMedia.roots(dirs)
            NoMedia.roots(dirs)
            NoMedia.directory(File(dirs.first(), ".thumbnails"))
            for (dir in dirs + File(dirs.first(), ".thumbnails")) assertTrue(File(dir, ".nomedia").isFile)
        } finally { root.deleteRecursively() }
    }

    @Test fun bulkThreadSetsLinuxBackgroundPriorityBeforeExecuting() {
        val done = CountDownLatch(1)
        var priority = 0
        var javaPriority = 0
        val thread = BulkWork.thread("bulk-priority-test", Runnable {
            priority = Process.getThreadPriority(Process.myTid())
            javaPriority = Thread.currentThread().priority
            done.countDown()
        })
        thread.start()
        assertTrue(done.await(5, TimeUnit.SECONDS))
        thread.join()
        assertEquals(Process.THREAD_PRIORITY_BACKGROUND, priority)
        assertEquals(Thread.MIN_PRIORITY, javaPriority)
    }

    @Test fun workMakesNoProgressUntilReadingEndsAndAnInterruptCancelsTheWait() {
        var reading = true
        var polls = 0
        var progress = 37
        BulkWork.awaitIdle({ reading }) {
            assertEquals(37, progress)
            if (++polls == 3) reading = false
        }
        progress++
        assertEquals(3, polls)
        assertEquals(38, progress)
        Thread.currentThread().interrupt()
        try {
            BulkWork.awaitIdle({ true }) { fail("must honour cancellation") }
            fail("must interrupt")
        } catch (_: InterruptedException) {
            assertTrue(Thread.interrupted())
        }
    }

    @Test fun actualReadingGateResumesBulkWorkWhenTheScreenSleeps() {
        val app = org.robolectric.RuntimeEnvironment.getApplication()
        val power = app.getSystemService(android.os.PowerManager::class.java)
        org.robolectric.Shadows.shadowOf(power).setIsInteractive(true)
        Prefs(app).readingAt = System.currentTimeMillis()
        BulkWork.attach(app)
        BulkWork.changed()
        val done = CountDownLatch(1)
        val thread = BulkWork.thread("reading-pause-test", Runnable { BulkWork.checkpoint(); done.countDown() })
        thread.start()
        try {
            val until = System.nanoTime() + 2_000_000_000L
            while (!BulkWork.paused && System.nanoTime() < until) Thread.sleep(5)
            assertTrue("foreground reading pauses bulk work", BulkWork.paused)
            assertEquals(1L, done.count)
            org.robolectric.Shadows.shadowOf(power).setIsInteractive(false)
            BulkWork.changed()
            assertTrue("screen sleep resumes work without a new command", done.await(2, TimeUnit.SECONDS))
        } finally {
            Prefs(app).readingAt = 0
            BulkWork.changed()
            thread.interrupt(); thread.join(2_000)
        }
    }

    @Test fun HomeVisibilityReportResumesBulkWorkWithoutRecordingABatteryMeasurement() = visibilityReport("home")
    @Test fun EndSheetVisibilityReportResumesBulkWorkWithoutRecordingABatteryMeasurement() = visibilityReport("end-of-book")
    @Test fun StorageVisibilityReportResumesBulkWorkWithoutRecordingABatteryMeasurement() = visibilityReport("storage")

    private fun visibilityReport(reason:String) {
        val app=org.robolectric.RuntimeEnvironment.getApplication()
        org.robolectric.Shadows.shadowOf(app.getSystemService(android.os.PowerManager::class.java)).setIsInteractive(true)
        val prefs=Prefs(app);prefs.readingAt=System.currentTimeMillis();BulkWork.attach(app);BulkWork.changed()
        val store=StatsStore.get(app);val recorder=StatsRecorder(app,prefs)
        val before=store.readableDatabase.rawQuery("SELECT count(*) FROM snap",null).use { it.moveToFirst();it.getLong(0) }
        val done=CountDownLatch(1);val thread=BulkWork.thread("home-visibility-test",Runnable { BulkWork.checkpoint();done.countDown() })
        thread.start()
        try {
            val until=System.nanoTime()+2_000_000_000L
            while(!BulkWork.paused && System.nanoTime()<until) Thread.sleep(5)
            assertTrue(BulkWork.paused)
            val report=android.content.Intent(Contract.STATS).putExtra("reason",reason).putExtra("reading","0").putExtra("open","1").putExtra("visibility_only","1")
            Reading.onStats(app,report);recorder.onStats(report)
            assertTrue(done.await(2,TimeUnit.SECONDS));assertFalse(Reading.now(app))
            val after=store.readableDatabase.rawQuery("SELECT count(*) FROM snap",null).use { it.moveToFirst();it.getLong(0) }
            assertEquals(before,after)
        } finally { prefs.readingAt=0;BulkWork.changed();thread.interrupt();thread.join(2000) }
    }

    @Test fun repeatedNetUpAndWifiCallbacksShareOneVpnAttemptUntilDisconnect() {
        val gate = VpnConnectGate()
        assertFalse(gate.request(false, false))
        assertTrue(gate.request(true, false))
        repeat(20) { assertFalse(gate.request(true, false)) }
        assertFalse(gate.request(true, true))
        assertFalse(gate.request(true, false)) // VPN loss alone must not hammer reconnect.
        gate.disconnected()
        assertTrue(gate.request(true, false))
        gate.disconnected()
        assertFalse(gate.request(true, true)) // Already up, including after process recreation.
        assertFalse(gate.request(true, false))
    }
}
