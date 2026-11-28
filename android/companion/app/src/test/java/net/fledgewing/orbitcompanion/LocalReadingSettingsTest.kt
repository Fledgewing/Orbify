// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

import android.os.Environment
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.TextView
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowLooper
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[34],qualifiers="w632dp-h840dp-port-xhdpi")
class LocalReadingSettingsTest {
    private val ledger get()=File(Environment.getExternalStorageDirectory(),"koreader/settings/booksync-local-reading.sqlite3")
    @Before fun setup() { ledger.delete();SettingsPage.forceLocked=false;Prefs(RuntimeEnvironment.getApplication()).mode=OrbitMode.FULL }
    @After fun cleanup() { ledger.delete();SettingsPage.forceLocked=null }
    private fun views(v:View):List<View> = listOf(v)+if(v is ViewGroup) (0 until v.childCount).flatMap { views(v.getChildAt(it)) } else emptyList()
    private fun texts(a:LocalReadingSettingsActivity)=views(a.window.decorView).filterIsInstance<TextView>()
    private fun waitFor(a:LocalReadingSettingsActivity,text:String) {
        val end=System.nanoTime()+TimeUnit.SECONDS.toNanos(5)
        while(texts(a).none {it.text.toString().contains(text)}) { ShadowLooper.idleMainLooper();check(System.nanoTime()<end);Thread.sleep(10) }
    }
    @Test fun companionNumericGoalSavesDisablesAndReopensThroughLibrary() {
        val controller=Robolectric.buildActivity(LocalReadingSettingsActivity::class.java).setup();val a=controller.get()
        waitFor(a,"Off · This reader only")
        texts(a).first {it.text.toString()=="Local reading goal"}.parent.parent.let { (it as View).performClick() }
        val input=views(a.window.decorView).filterIsInstance<EditText>().single()
        assertEquals(android.text.InputType.TYPE_CLASS_NUMBER,input.inputType)
        input.setText("12")
        // Approved form: compact input and adjacent actions, including on the smaller reader.
        val decor = a.window.decorView
        val metrics = a.resources.displayMetrics
        decor.measure(View.MeasureSpec.makeMeasureSpec(metrics.widthPixels, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(metrics.heightPixels, View.MeasureSpec.EXACTLY))
        decor.layout(0, 0, metrics.widthPixels, metrics.heightPixels)
        val off = texts(a).first { it.text.toString() == "Off" }
        val save = texts(a).first { it.text.toString() == "Save" }
        assertEquals("form actions share one row", off.top, save.top)
        assertTrue("Save follows Off without overlap", save.left >= off.right)
        assertTrue("a three-digit goal remains a compact field", input.width < metrics.widthPixels / 2)
        texts(a).first {it.text.toString()=="Save"}.performClick()
        waitFor(a,"12 books · This reader only")
        controller.pause().stop().destroy()
        val second=Robolectric.buildActivity(LocalReadingSettingsActivity::class.java).setup();val b=second.get()
        waitFor(b,"12 books · This reader only")
        texts(b).first {it.text.toString()=="Local reading goal"}.parent.parent.let { (it as View).performClick() }
        texts(b).first {it.text.toString()=="Off"}.performClick()
        waitFor(b,"Off · This reader only")
        second.pause().stop().destroy()
    }
    @Test fun legacyImportCannotBlockNativeIntentWhileReading() {
        val app=RuntimeEnvironment.getApplication()
        val settings=ledger.parentFile!!
        settings.mkdirs()
        val source=File(settings,"orbit-finish-queue.lua")
        val original=source.takeIf {it.isFile}?.readBytes()
        val book=File(Environment.getExternalStorageDirectory(),"ledger-gate-fixture/book.epub")
        book.parentFile!!.mkdirs();book.writeText("synthetic")
        val metadata=File(book.parentFile,"book.sdr/metadata.epub.lua");metadata.parentFile!!.mkdirs()
        val digest="c".repeat(32);val now=System.currentTimeMillis()/1000
        val day=java.time.LocalDate.now().toString()
        metadata.writeBytes("return ".toByteArray()+LuaValue.encode(mapOf("partial_md5_checksum" to digest,"summary" to mapOf("status" to "complete","modified" to day))))
        source.writeBytes("return ".toByteArray()+LuaValue.encode(mapOf("jobs" to mapOf(digest to mapOf("hash" to digest,"file" to book.path,"finished_on" to day,"created_at" to now)))))
        // Warm native SQLite/class loading before the liveness assertion. A changed
        // source stamp forces the same proven import to run again under the reading gate.
        LibraryLocalReading.snapshot(settings)
        source.appendText("\n")
        org.robolectric.Shadows.shadowOf(app.getSystemService(android.os.PowerManager::class.java)).setIsInteractive(true)
        Prefs(app).readingAt=System.currentTimeMillis();BulkWork.attach(app);BulkWork.changed()
        val imported=CountDownLatch(1);val persisted=CountDownLatch(1)
        val thread=Thread { try { LibraryLocalReading.snapshot(settings) } finally { imported.countDown() } }
        thread.start()
        try {
            assertTrue("local import must not wait for reading under the ledger lock",imported.await(2,TimeUnit.SECONDS))
            val document="d".repeat(32)
            LibraryLocalReading.command("reading.local.event",mapOf("document" to document,"revision" to 1L,"token" to "$document:1","complete" to true,"at" to now)) { value,error ->
                assertNull(error);assertEquals(2L,value!!["books_this_year"]);persisted.countDown()
            }
            assertTrue("native intent must checkpoint during reading",persisted.await(2,TimeUnit.SECONDS))
            assertTrue(Reading.now(app))
        } finally {
            Prefs(app).readingAt=0;BulkWork.changed();thread.interrupt();thread.join(2000)
            if(original==null) source.delete() else source.writeBytes(original)
            book.parentFile!!.deleteRecursively()
        }
    }
    @Test fun lockedStatisticsShowLocalValuesWithoutAnEditor() {
        SettingsPage.forceLocked=true
        val c=Robolectric.buildActivity(LocalReadingSettingsActivity::class.java).setup();val a=c.get()
        waitFor(a,"This reader only")
        assertTrue(views(a.window.decorView).filterIsInstance<EditText>().isEmpty())
        assertTrue(texts(a).any {it.text.toString()=="Finished this year"})
        c.pause().stop().destroy()
    }
}
