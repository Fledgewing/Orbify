package net.fledgewing.orbitcompanion

import android.app.Activity
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import net.fledgewing.orbitcompanion.Checklist.Row
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * The Setup page's states drawn by ChecklistUi against Robolectric (docs/design/emulated-release-tests.md,
 * stage 2; companion-checklist §6): what each state shows, which buttons exist, and that
 * readable type survives a smaller reader viewport without being shrunk to fit.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w632dp-h840dp-port-xhdpi")
class ChecklistPageTest {
    private val activity: Activity = Robolectric.buildActivity(Activity::class.java).setup().get()

    private val rows = listOf(
        Row("koreader", "KOReader", true, "Version 2025.10", short = "KOReader 2025.10"),
        Row("plugin", "BookOrbit plugin", true, "Version 1.8"),
        Row("patch", "BookSync plugin", true, "Version 0.11.2", short = "BookSync plugin 0.11.2", pinFree = true),
        Row("signed_in", "BookOrbit account", true, "Signed in", short = "Signed in", verb = "Sign in"),
        Row("recommended", "Recommended settings", true, "Applied", short = "recommended settings on", verb = "Review"),
        Row("home", "Home app", true, "BookSync is the Home app", verb = "Set"),
        Row("install_updates", "Install apps", true, "Allowed", verb = "Allow"),
        Row("notifications", "Notifications", true, "Allowed", verb = "Allow"),
        BatteryMerge.row(listOf(BatteryMerge.App("BookSync", BatteryRow.Row(true, "done"), locked = true), BatteryMerge.App("KOReader", BatteryRow.Row(true, "done")))),
        Row("admin", "Screen lock", true, "Allowed", verb = "Allow"),
        Row("tailscale", "Tailscale", true, "Connected", short = "Tailscale connected", verb = "Connect"),
        Row("wifi_test", "Wi-Fi off/on test", true, "Passed 17:02", short = "Wi-Fi test passed 17:02", info = true, verb = "Run"),
        Row("screen_saver", "Screen saver from BookSync", false, optional = true, verb = "Show how"),
    )

    private fun open(vararg ids: String) = rows.map { if (it.id in ids) it.copy(done = false, stateLine = "Not yet") else it }

    private val frame = ChecklistUi.Frame(
        tips = listOf(ChecklistUi.Tip("play_protect", "Play Protect scans installs", "…")),
        detailsLine = "Last heard from KOReader 17:19",
        modeLine = "Full mode · change in Settings",
    )

    private class Taps : ChecklistUi.Actions {
        val log = mutableListOf<String>()
        override fun verb(i: Checklist.Item) { log += "verb ${i.id}" }
        override fun tap(i: Checklist.Item) { log += "tap ${i.id}" }
        override fun summaryButton() { log += "summary" }
        override fun group(key: String) { log += "group $key" }
        override fun gotIt(tipId: String) { log += "got $tipId" }
        override fun showHiddenTips() { log += "hidden" }
        override fun details() { log += "details" }
        override fun mode() { log += "mode" }
    }

    private fun draw(page: Checklist.Page, f: ChecklistUi.Frame = frame, taps: Taps = Taps()): LinearLayout =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            addView(Ui.header(activity, "Setup", "‹ Back") {})
            ChecklistUi.render(activity, this, page, f, taps)
        }

    private fun texts(v: View): List<String> = when (v) {
        is TextView -> listOf(v.text.toString())
        is ViewGroup -> (0 until v.childCount).flatMap { texts(v.getChildAt(it)) }
        else -> emptyList()
    }

    /** Buttons: clickable TextViews (Ui.button). */
    private fun buttons(v: View): List<String> = when (v) {
        is TextView -> if (v.hasOnClickListeners()) listOf(v.text.toString()) else emptyList()
        is ViewGroup -> (0 until v.childCount).flatMap { buttons(v.getChildAt(it)) }
        else -> emptyList()
    }

    /** Taps the text's nearest clickable view (a row's label taps the row). */
    private fun click(root: View, text: String): Boolean {
        var v: View? = findText(root, text)
        while (v != null && !v.hasOnClickListeners()) v = v.parent as? View
        return v?.performClick() ?: false
    }

    private fun Checklist.Page.drawn(f: ChecklistUi.Frame = frame) = draw(this, f)

    @Test
    fun allSetKeepsReadableTypeAndAllowsScrolling() {
        val root = Checklist.page(Checklist.items(rows)).drawn()
        val t = texts(root)
        assertTrue(t.contains("All set"))
        assertTrue(t.contains("Everything this reader needs is done. Optional items below."))
        assertTrue(t.contains("KOReader 2025.10, BookOrbit plugin, BookSync plugin 0.11.2"))
        assertTrue(t.contains("Screen saver from BookSync: off"))
        assertTrue(t.contains("Full mode · change in Settings"))
        assertFalse("no verbs on a set-up reader", buttons(root).any { it in setOf("Sign in", "Allow", "Set", "Fix next") })
        val d = activity.resources.displayMetrics
        assertEquals(1264, d.widthPixels)
        // Measure all content at the actual page inset; its ScrollView owns the viewport.
        val pad = Ui.dp(activity, CompanionStyle.PAGE_INSET) * 2
        root.measure(View.MeasureSpec.makeMeasureSpec(d.widthPixels - pad, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        // Round 2: keep the shared readable scale; the real EinkActivity page scrolls.
        assertTrue("all groups retain their touch height", root.measuredHeight >= Ui.dp(activity, Ui.ROW_DP) * 4)
        fun verify(v: View) {
            if (v is TextView && v.text.any { it.isLetterOrDigit() }) {
                val minimum = CompanionStyle.MIN_BODY * (632f / 749f) * d.scaledDensity
                assertTrue("${v.text}: text was shrunk to fit", v.textSize >= minimum - 0.5f)
            }
            if (v is ViewGroup) (0 until v.childCount).forEach { verify(v.getChildAt(it)) }
        }
        verify(root)
    }

    @Test
    fun needsYouRowsShowLossLinesAndOneVerb() {
        val items = Checklist.items(open("signed_in", "notifications"), lastDone = setOf("notifications"))
        val root = Checklist.page(items).drawn()
        val t = texts(root)
        assertTrue(t.contains("2 things need you"))
        assertTrue(t.contains("NEEDS YOU"))
        assertTrue(t.any { it.contains("Until then: nothing syncs.") })
        assertTrue(t.any { it.startsWith("Stopped working: ") })
        assertTrue(t.contains("1 needs you · recommended settings on"))
        val b = buttons(root)
        assertTrue(b.containsAll(listOf("Fix next", "Sign in", "Allow")))
    }

    @Test
    fun aGroupExpandsInPlaceOneAtATime() {
        val items = Checklist.items(rows)
        val closed = texts(Checklist.page(items).drawn())
        assertFalse(closed.contains("Home app"))
        val open = texts(Checklist.page(items).drawn(frame.copy(open = Checklist.Group.PERMISSIONS.name)))
        assertTrue(open.contains("Home app"))
        assertTrue(open.contains("Battery"))
        assertTrue("the open group's rows, not another's", !open.contains("KOReader"))
        val taps = Taps()
        val root = draw(Checklist.page(items), taps = taps)
        assertTrue(click(root, "Apps"))
        assertEquals(listOf("group APPS"), taps.log)
    }

    @Test
    fun setByTheReaderShowsItsMark() {
        val t = texts(Checklist.page(Checklist.items(rows)).drawn(frame.copy(open = Checklist.Group.PERMISSIONS.name)))
        assertTrue(t.any { it.startsWith("Unrestricted for KOReader · set by the reader for BookSync") })
    }

    @Test
    fun skippedAndOptionalRowsSayWithoutItInBothModes() {
        val items = Checklist.items(open("admin"), ignored = setOf("admin"))
        val perms = texts(Checklist.page(items).drawn(frame.copy(open = Checklist.Group.PERMISSIONS.name)))
        assertTrue(perms.any { it.startsWith("Skipped\nWithout it: Sync and sleep asks you to press the power button.") })
        val opt = texts(Checklist.page(items).drawn(frame.copy(open = Checklist.Group.OPTIONAL.name)))
        assertTrue(opt.any { it.contains("Without it: ${Checklist.LOSS.getValue("screen_saver")}") })
    }

    @Test
    fun checkingIsStaticText() {
        val items = Checklist.items(rows.map { if (it.id == "signed_in") it.copy(done = false, pending = true, verb = null) else it })
        val t = texts(Checklist.page(items).drawn())
        assertTrue(t.contains("Checking…"))
        assertTrue(t.contains("Waiting for KOReader to report. Open KOReader once."))
    }

    @Test
    fun firstRunNumbersTheSteps() {
        val root = Checklist.page(Checklist.items(open("koreader", "home")), firstRun = true).drawn()
        val t = texts(root)
        assertTrue(t.contains("Let's set up this reader"))
        assertTrue(t.contains("STEPS"))
        assertTrue(t.containsAll(listOf("1", "2")))
        assertTrue(buttons(root).contains("Start"))
    }

    @Test
    fun lockedPinViewNeedsAGrownUp() {
        val r = open("tailscale", "notifications").map { if (it.id == "patch") it.copy(pending = true, verb = "Restart KOReader") else it }
        val root = Checklist.page(Checklist.items(r), locked = true).drawn(frame.copy(hiddenTips = 1))
        val t = texts(root)
        assertTrue(t.contains("2 things need a grown-up"))
        assertTrue(t.contains("NEEDS A GROWN-UP"))
        assertTrue(t.contains("READY NOW"))
        val b = buttons(root)
        assertTrue(b.containsAll(listOf("Unlock to fix", "Restart KOReader")))
        assertFalse(b.any { it in setOf("Connect", "Allow", "Fix next", "Show how") })
        assertFalse("mode link hidden", root.let { v -> findText(v, "Full mode · change in Settings")!!.hasOnClickListeners() })
    }

    @Test
    fun newInTagShowsOnTheRow() {
        val items = Checklist.items(open("keyboard") + Row("keyboard", "BookSync keyboard", false, verb = "Turn on")) { r -> if (r.id == "keyboard") "New in 0.12" else null }
        val t = texts(Checklist.page(items).drawn())
        assertTrue(t.any { it.startsWith("BookSync keyboard  [NEW IN 0.12]") })
    }

    @Test
    fun statusCardMatchesTheSummary() {
        val items = Checklist.items(open("signed_in"))
        val card = ChecklistUi.statusCard(activity, Checklist.summary(items), items) {}
        assertEquals(listOf("", "Setup: 1 thing needs you ›", "BookOrbit account · tap to fix"), texts(card))
    }

    private fun findText(v: View, text: String): TextView? = when (v) {
        is TextView -> v.takeIf { it.text.toString() == text }
        is ViewGroup -> (0 until v.childCount).firstNotNullOfOrNull { findText(v.getChildAt(it), text) }
        else -> null
    }

    // The real pages, with the device Robolectric gives them: they draw without crashing.

    @Test
    fun setupPageDrawsOnTheDevice() {
        Prefs(activity).mode = OrbitMode.FULL
        val a = Robolectric.buildActivity(SetupActivity::class.java).setup().get()
        val t = texts(a.window.decorView)
        assertTrue(t.contains("Setup"))
        assertTrue(t.any { it.startsWith("Details") })
        assertTrue(t.any { it.endsWith("need you") || it.endsWith("needs you") || it == "All set" || it == "Checking…" })
    }

    @Test
    fun detailsPageHasCopyForSupport() {
        val a = Robolectric.buildActivity(SetupDetailsActivity::class.java).setup().get()
        // Details publishes asynchronously. A second Library callback is a FIFO barrier
        // after the Activity's request; drain the main queue before inspecting its rows.
        val ready = java.util.concurrent.atomic.AtomicBoolean(false)
        LibraryDiagnostics.snapshot(a) { ready.set(true) }
        val deadline = System.nanoTime() + 10_000_000_000L
        while (!ready.get() && System.nanoTime() < deadline) {
            org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
            Thread.sleep(10)
        }
        assertTrue("Library diagnostics callback missing", ready.get())
        val t = texts(a.window.decorView)
        assertFalse("Diagnostics callback did not finish", t.contains("Loading crash summaries…"))
        assertTrue(t.contains("BookSync plugin last answered"))
        assertTrue(buttons(a.window.decorView).contains("Copy for support"))
    }

    @Test
    fun batteryDetailListsEachApp() {
        val a = Robolectric.buildActivity(SetupBatteryActivity::class.java).setup().get()
        assertTrue(texts(a.window.decorView).contains("BookSync"))
    }
}
