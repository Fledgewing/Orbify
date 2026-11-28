package net.fledgewing.orbitcompanion

import android.app.Activity
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ScrollView
import android.widget.TextView
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/**
 * The M8C feedback of 2026-11-24 against Robolectric, at the M8C's size (1264 × 1680, xhdpi) and
 * a small phone's (360 × 640 dp): the header stays pinned, search clears with ✕, a row's text
 * never runs into its control, a page's title shows once, "Waiting for KOReader" has its own
 * line, single-row sections open their page directly, and the main view puts Setup right under
 * Other apps / Settings.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w632dp-h840dp-port-xhdpi")
class PageLayoutTest {
    private val schema = SettingsSchema.parse(File("../../../shared/settings/schema.json").readText())
    private val app get() = RuntimeEnvironment.getApplication()

    @Before
    fun setUp() {
        SettingsStore.useSchema(schema)
        Prefs(app).mode = OrbitMode.FULL
        SettingsPage.forceLocked = false
    }

    @After
    fun tearDown() {
        SettingsPage.forceLocked = null
    }

    private fun all(v: View): List<View> = listOf(v) + if (v is ViewGroup) (0 until v.childCount).flatMap { all(v.getChildAt(it)) } else emptyList()
    private fun texts(a: Activity): List<String> = all(a.window.decorView).filterIsInstance<TextView>().map { it.text.toString() }
    private fun tagged(a: Activity, tag: String): View? = all(a.window.decorView).firstOrNull { it.tag == tag }

    private inline fun <reified T : Activity> open(intent: Intent? = null): T =
        (if (intent == null) Robolectric.buildActivity(T::class.java) else Robolectric.buildActivity(T::class.java, intent)).setup().visible().get()

    /** Lays the page out at the configured screen size. */
    private fun layout(a: Activity) {
        val dm = a.resources.displayMetrics
        val root = a.window.decorView
        root.measure(View.MeasureSpec.makeMeasureSpec(dm.widthPixels, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(dm.heightPixels, View.MeasureSpec.EXACTLY))
        root.layout(0, 0, dm.widthPixels, dm.heightPixels)
    }

    /**
     * The page as drawn (native graphics), whole content height, into build/screenshots/<name>.png:
     * the pictures that go with a UI change. Never compared: the asserts are the test.
     */
    private fun shot(a: Activity, name: String) {
        layout(a)
        val scroll = all(a.window.decorView).filterIsInstance<ScrollView>().firstOrNull()
        val extra = scroll?.let { maxOf(0, it.getChildAt(0).height - it.height) } ?: 0
        val v = a.window.decorView
        val dm = a.resources.displayMetrics
        if (extra > 0) {
            v.measure(View.MeasureSpec.makeMeasureSpec(dm.widthPixels, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(dm.heightPixels + extra, View.MeasureSpec.EXACTLY))
            v.layout(0, 0, dm.widthPixels, dm.heightPixels + extra)
        }
        val bmp = android.graphics.Bitmap.createBitmap(v.width, v.height, android.graphics.Bitmap.Config.ARGB_8888)
        v.draw(android.graphics.Canvas(bmp))
        val out = File("build/screenshots").apply { mkdirs() }
        File(out, "$name-${dm.widthPixels}x${dm.heightPixels}.png").outputStream().use { bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        layout(a)
    }

    private fun onScreenY(v: View): Int = IntArray(2).also { v.getLocationInWindow(it) }[1]

    private fun sleepPage(): SleepScreenActivity {
        SettingsStore.set(app, "sleep_mode", "recommended", "test")
        SettingsStore.set(app, "sleep_style", "overlay", "test")
        return open()
    }

    private fun assertHeaderPinned(a: Activity) {
        layout(a)
        val header = all(a.window.decorView).first { it is HeaderBar }
        assertEquals("the header sits in the pinned slot", PINNED_TAG, (header.parent as View).tag)
        val scroll = all(a.window.decorView).filterIsInstance<ScrollView>().first()
        assertFalse("the header is not inside the scrolling part", all(scroll).contains(header))
        val y = onScreenY(header)
        scroll.scrollTo(0, 600)
        layout(a)
        assertTrue("the page did scroll", scroll.scrollY > 0)
        assertEquals("the header did not move", y, onScreenY(header))
        assertTrue("‹ Settings stays on screen", all(header).filterIsInstance<TextView>().any { it.text.toString() == "‹ Settings" })
    }

    @Test
    fun theHeaderStaysPinnedWhileTheSettingsScroll() {
        val a = sleepPage()
        shot(a, "sleep-screen")
        assertHeaderPinned(a)
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-port-xxhdpi")
    fun theHeaderStaysPinnedOnASmallPhone() {
        val a = sleepPage()
        shot(a, "sleep-screen")
        assertHeaderPinned(a)
    }

    @Test
    fun searchClearsWithTheCrossAtTheRightOfTheBox() {
        val a = open<SettingsActivity>()
        val box = tagged(a, "search") as EditText
        val clear = tagged(a, "search:clear")!!
        assertEquals("nothing to clear yet", View.GONE, clear.visibility)
        box.setText("sleep")
        assertEquals(View.VISIBLE, clear.visibility)
        shot(a, "search")
        layout(a)
        assertTrue("✕ is at the right end of the input", clear.left >= box.right && (clear.parent as View) == box.parent)
        clear.performClick()
        assertEquals("", box.text.toString())
        assertNotNull("the sections at once, no pause", tagged(a, "section:sleep"))
        assertEquals(View.GONE, clear.visibility)
    }

    /** Every row with a control: the text column ends a fixed gap before it, and both have room. */
    private fun assertNoOverlap(a: Activity) {
        layout(a)
        val gap = Ui.dp(a, Ui.ROW_GAP_DP)
        val rows = all(a.window.decorView).filterIsInstance<RowLayout>().filter { it.control != null && it.width > 0 }
        assertTrue("rows to check", rows.isNotEmpty())
        rows.forEach { r ->
            val text = all(r).first { it.tag == Ui.ROW_TEXT_TAG }
            val c = r.control!!
            val what = (all(text).filterIsInstance<TextView>().firstOrNull()?.text ?: "?").toString()
            assertTrue("$what: text has room (${text.width})", text.width > 0)
            assertTrue("$what: control has room", c.width > 0)
            assertTrue("$what: text ends ${c.left - text.right}px before the control, at least $gap", c.left - text.right >= gap)
            assertTrue("$what: control capped", c !is TextView || c.width <= (r.width * Ui.CONTROL_MAX).toInt() + 1)
        }
    }

    @Test
    fun rowTextNeverRunsIntoItsControl() {
        listOf("library", "sync", "reading", "updates").forEach { assertNoOverlap(open<SettingsSectionActivity>(SettingsPage.section(app, it))) }
        assertNoOverlap(sleepPage())
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-port-xxhdpi")
    fun rowTextNeverRunsIntoItsControlOnASmallPhone() {
        listOf("library", "sync", "reading", "updates").forEach { assertNoOverlap(open<SettingsSectionActivity>(SettingsPage.section(app, it))) }
        assertNoOverlap(sleepPage())
    }

    @Test
    fun aLongValueWrapsInsteadOfPushingTheTextOut() {
        val a = open<SettingsActivity>()
        val long = Ui.value(a, "Up next in series, Want to read, Discover, Romance (list)  ›")
        val row = Ui.row(a, "Applies when KOReader restarts and a few more words", "A line that is long enough to wrap twice on a phone", long)
        (tagged(a, "section:sleep")!!.parent as ViewGroup).addView(row)
        assertNoOverlap(a)
        assertTrue("the value wraps", long.lineCount > 1)
    }

    /** Pick from with several ticked (R1c): drawn for the screenshots, the header pinned. */
    @Test
    fun pickFromShowsTickBoxes() {
        SettingsStore.set(app, "sleep_mode", "recommended", "test")
        SettingsStore.set(app, "sleep_from", "up_next\ndiscover", "test")
        val a = open<SettingChoiceActivity>(Intent(app, SettingChoiceActivity::class.java).putExtra(SettingsPage.EXTRA_KEY, "sleep_from"))
        shot(a, "pick-from")
        assertNotNull(tagged(a, "option:library"))
        assertTrue(all(a.window.decorView).any { it is HeaderBar && (it.parent as View).tag == PINNED_TAG })
    }

    @Test
    fun aPageTitleShowsOnce() {
        val a = sleepPage()
        assertEquals("Sleep screen", 1, texts(a).count { it == "Sleep screen" })
        assertNotNull("its choice is still there", tagged(a, "key:sleep_mode"))
    }

    @Test
    fun waitingForKoreaderHasALineOfItsOwn() {
        val a = open<SettingsSectionActivity>(SettingsPage.section(app, "library"))
        tagged(a, "key:offline_cache")!!.performClick()
        val b = open<SettingsSectionActivity>(SettingsPage.section(app, "library"))
        val line = all(tagged(b, "key:offline_cache")!!).filterIsInstance<TextView>().map { it.text.toString() }.first { it.contains("Waiting") }
        assertTrue(line, line.endsWith("Applies when KOReader restarts.\n${SettingsUi.WAITING}"))
    }

    @Test
    fun singleRowSectionsOpenTheirPageDirectly() {
        val a = open<SettingsActivity>()
        tagged(a, "section:buttons")!!.performClick()
        assertEquals(ClickersActivity::class.java.name, shadowOf(a).nextStartedActivity.component?.className)
        tagged(a, "section:kids")!!.performClick()
        assertEquals("no PIN yet: set one", PinActivity::class.java.name, shadowOf(a).nextStartedActivity.component?.className)
        tagged(a, "section:sync")!!.performClick()
        assertEquals(SettingsSectionActivity::class.java.name, shadowOf(a).nextStartedActivity.component?.className)
        Prefs(app).mode = OrbitMode.ADDON
        val b = open<SettingsActivity>()
        tagged(b, "section:buttons")!!.performClick()
        assertEquals("Add-on: the helper switch is a second row", SettingsSectionActivity::class.java.name, shadowOf(b).nextStartedActivity.component?.className)
    }

    private fun assertMainViewSetupUnderButtons(): LauncherActivity {
        val a = open<LauncherActivity>()
        layout(a)
        val settings = all(a.window.decorView).filterIsInstance<TextView>().first { it.text.toString().contains("Settings") }
        val card = tagged(a, "status:setup")!!
        val row = settings.parent.parent as View
        val column = row.parent as ViewGroup
        val after = (column.indexOfChild(row) + 1 until column.childCount).map { column.getChildAt(it) }.first { it.height > Ui.dp(a, 12) }
        assertEquals("Setup comes right after Other apps / Settings", card, after)
        assertFalse("no second \"setup steps need you\" line", texts(a).any { it.contains("setup step") })
        return a
    }

    @Test
    fun theMainViewFitsOnTheM8cScreenWithSetupUnderTheButtons() {
        val a = assertMainViewSetupUnderButtons()
        shot(a, "main")
        val scroll = all(a.window.decorView).filterIsInstance<ScrollView>().first()
        val content = scroll.getChildAt(0)
        assertTrue("fits without scrolling: ${content.height} <= ${scroll.height}", content.height <= scroll.height)
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-port-xxhdpi")
    fun theMainViewKeepsSetupUnderTheButtonsOnASmallPhone() {
        val a = assertMainViewSetupUnderButtons()
        shot(a, "main")
        val card = tagged(a, "status:setup")!!
        assertTrue("Setup is on the first screen", onScreenY(card) + card.height <= a.resources.displayMetrics.heightPixels)
    }
    private fun aboutNoticeWraps(): AboutActivity {
        val a = open<AboutActivity>()
        layout(a)
        val credits = org.json.JSONObject(File("../../../shared/about/credits.json").readText())
        val paragraphs = credits.getJSONArray("paragraphs")
        for (i in 0 until paragraphs.length()) {
            val view = all(a.window.decorView).filterIsInstance<TextView>().first { it.text.toString() == paragraphs.getString(i) }
            assertTrue("notice has no ellipsis", (0 until view.lineCount).all { view.layout.getEllipsisCount(it) == 0 })
            assertTrue("notice wraps within the page", view.width <= a.resources.displayMetrics.widthPixels)
        }
        shot(a, "about")
        return a
    }

    @Test
    fun aboutNoticeWrapsOnTheReader() { aboutNoticeWraps() }

    @Test
    @Config(qualifiers = "w360dp-h640dp-port-xxhdpi")
    fun aboutNoticeWrapsOnASmallPhone() { aboutNoticeWraps() }

}
