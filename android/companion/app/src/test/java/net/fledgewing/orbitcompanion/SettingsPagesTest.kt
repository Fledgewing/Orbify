package net.fledgewing.orbitcompanion

import android.app.Activity
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.TextView
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowLooper
import java.io.File

/**
 * The Settings pages against Robolectric (docs/design/companion-settings.md §5): the top page's
 * eight sections and search, each section's rows from the schema, the queued-change mark, and the
 * read-only view behind the PIN.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w632dp-h840dp-port-xhdpi")
class SettingsPagesTest {
    private val schema = SettingsSchema.parse(File("../../../shared/settings/schema.json").readText())

    @Before
    fun setUp() {
        SettingsStore.useSchema(schema)
        Prefs(RuntimeEnvironment.getApplication()).mode = OrbitMode.FULL
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
        (if (intent == null) Robolectric.buildActivity(T::class.java) else Robolectric.buildActivity(T::class.java, intent)).setup().get()

    private fun section(id: String, focus: String? = null): SettingsSectionActivity =
        open(SettingsPage.section(RuntimeEnvironment.getApplication(), id, focus).setClass(RuntimeEnvironment.getApplication(), SettingsSectionActivity::class.java))

    @Test
    fun reminderInformationIsSearchableAndReadableWithoutUnlocking() {
        for(query in listOf("reminder","bedtime","eye rest")) assertTrue(SettingsUi.search(schema,query).any {it.id=="reminders"})
        SettingsPage.forceLocked=true
        val a=section("reading")
        assertTrue(texts(a).contains("Reminders"))
        assertTrue(texts(a).contains("Set reminders in BookSync reader settings"))
        assertNull(shadowOf(a).nextStartedActivity)
    }

    @Test
    fun aboutIsReachableWhileLockedAndShowsSharedCreditWithBrowserLink() {
        SettingsPage.forceLocked = true
        val settings = open<SettingsActivity>()
        val row = tagged(settings, "about")!!
        assertTrue(row.isEnabled)
        row.performClick()
        assertEquals(AboutActivity::class.java.name, shadowOf(settings).nextStartedActivity.component!!.className)
        val about = open<AboutActivity>()
        assertEquals(PinPage.NEUTRAL, about.pinPage)
        val credits = org.json.JSONObject(File("../../../shared/about/credits.json").readText())
        val paragraphs = credits.getJSONArray("paragraphs")
        for (i in 0 until paragraphs.length()) assertTrue(texts(about).contains(paragraphs.getString(i)))
        assertFalse(texts(about).any { it.contains("powered by", ignoreCase = true) })
        tagged(about, "bookorbit-credit")!!.performClick()
        val link = shadowOf(about).nextStartedActivity
        assertEquals(Intent.ACTION_VIEW, link.action)
        assertEquals(credits.getString("url"), link.dataString)
    }

    @Test
    fun topPageListsTheEightSections() {
        val a = open<SettingsActivity>()
        schema.sections.forEach { s -> assertNotNull(s.id, tagged(a, "section:${s.id}")) }
        assertTrue(texts(a).contains("Sync and Wi-Fi"))
    }

    @Test
    fun searchFindsBySearchWordsAfterAPause() {
        val a = open<SettingsActivity>()
        (tagged(a, "search") as EditText).setText("screensaver")
        assertNotNull("sections stay until the pause", tagged(a, "section:sleep"))
        ShadowLooper.idleMainLooper(SettingsActivity.SEARCH_PAUSE_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
        assertNull(tagged(a, "section:sleep"))
        assertNotNull(tagged(a, "hit:sleep_mode"))
        (tagged(a, "search") as EditText).setText("zzzz")
        ShadowLooper.idleMainLooper(SettingsActivity.SEARCH_PAUSE_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
        assertTrue(texts(a).any { it.startsWith("Nothing matches") })
    }

    @Test
    fun updateChannelRowsShowDescriptionsAndSetTheUpdaterPreference() {
        val a = section("updates")
        assertTrue(texts(a).containsAll(listOf("Stable", "RC", "Preview", "tested releases only",
            "also release candidates, about to become stable", "every test build")))
        for (channel in UpdateChannel.values()) {
            tagged(a, "channel:${channel.key}")!!.performClick()
            assertEquals(channel, Prefs(a).updateChannel)
            assertEquals(channel.key, SettingsStore.get(a, "update_channel"))
        }
    }

    @Test
    fun everyShownKeyHasARowInItsSection() {
        // Defaults: sleep screen off hides its children; Wi-Fi rows need the wifi cap (Full has it).
        val hiddenByDefault = setOf("sleep_from", "sleep_leave_out", "sleep_hours", "sleep_text", "sleep_battery", "sleep_style",
            "sleep_text_position", "sleep_battery_corner", "home_button", "wifi_idle_min",
            // Sync: OrbiSmart (the default) sets these and hides them; Custom shows them (below).
            "sync_on_sleep", "sleep_cap", "sync_on_wake", "reading_schedule")
        schema.sections.filter { it.id != "sleep" }.forEach { s ->
            val a = section(s.id)
            schema.settings.filter { it.section == s.id && !it.hidden && it.key !in hiddenByDefault }.forEach { d ->
                assertNotNull("${s.id}: ${d.key}", tagged(a, "key:${d.key}"))
            }
        }
    }

    @Test
    fun syncCustomShowsTheRowsOrbiSmartHides() {
        val hidden = listOf("sync_on_sleep", "sleep_cap", "sync_on_wake", "reading_schedule")
        val smart = section("sync")
        assertNotNull(tagged(smart, "key:sync_mode"))
        assertTrue(texts(smart).contains("Reading position"))
        assertTrue(texts(smart).contains("Furthest page wins"))
        assertTrue(texts(smart).contains("BookSync keeps the furthest place you've read on any device, and asks before jumping."))
        hidden.forEach { assertNull("OrbiSmart hides $it", tagged(smart, "key:$it")) }
        SettingsStore.set(RuntimeEnvironment.getApplication(), "sync_mode", "custom", "test")
        val custom = section("sync")
        hidden.forEach { assertNotNull("Custom shows $it", tagged(custom, "key:$it")) }
    }

    @Test
    fun aChangeShowsWaitingForKoreaderUntilEchoed() {
        val a = section("library")
        tagged(a, "key:mirror_covers")!!.performClick()
        assertEquals("1", SettingsStore.get(a, "mirror_covers"))
        assertTrue(texts(a).any { it.contains("Waiting for KOReader") })
        val at = SettingsStore.at(a, "mirror_covers")!!
        SettingsStore.fromPlugin(a, SettingsSync.valuesJson(mapOf("mirror_covers" to SettingEntry("1", at))), "test")
        val b = section("library")
        assertFalse(texts(b).any { it.contains("Waiting for KOReader") })
    }

    @Test
    fun lockedIsReadOnlyWithUnlock() {
        SettingsPage.forceLocked = true
        val a = section("library")
        assertTrue(texts(a).contains("Unlock"))
        val row = tagged(a, "key:mirror_covers")!!
        assertFalse("no control while locked", row.hasOnClickListeners())
        assertFalse(texts(a).contains("Do now"))
        val top = open<SettingsActivity>()
        assertTrue("the top page still opens", tagged(top, "section:sync")!!.hasOnClickListeners())
    }

    @Test
    fun sleepScreenEditsPickFromLeaveOutAndText() {
        SettingsStore.set(RuntimeEnvironment.getApplication(), "sleep_mode", "recommended", "test")
        val a = open<SleepScreenActivity>()
        listOf("sleep_from", "sleep_leave_out", "sleep_text", "sleep_hours").forEach { k ->
            val row = tagged(a, "key:$k")
            assertNotNull(k, row)
        }
        assertNotNull("Sharp covers' slot sits in the section", tagged(a, "slot:sharp_covers"))
        assertNotNull("the clearing flash", tagged(a, "key:sleep_flash"))
        val hours = open<SettingChoiceActivity>(Intent(a, SettingChoiceActivity::class.java).putExtra(SettingsPage.EXTRA_KEY, "sleep_hours"))
        val options = all(hours.window.decorView).mapNotNull { (it.tag as? String)?.takeIf { t -> t.startsWith("option:") } }
        assertEquals("Every sleep is listed first", "option:0", options.first())
        assertTrue("Pick from opens the picker", tagged(a, "key:sleep_from")!!.hasOnClickListeners())
        tagged(a, "key:sleep_from")!!.performClick()
        assertEquals(SettingChoiceActivity::class.java.name, shadowOf(a).nextStartedActivity.component?.className)
    }

    /** R1c, X8: Pick from and Leave out tick several items on one page; Library stands alone; both sync per key. */
    @Test
    fun pickFromAndLeaveOutAreMultiSelectWithLibrary() {
        val app = RuntimeEnvironment.getApplication()
        SettingsStore.set(app, "sleep_mode", "recommended", "test")
        val pick = open<SettingChoiceActivity>(Intent(app, SettingChoiceActivity::class.java).putExtra(SettingsPage.EXTRA_KEY, "sleep_from"))
        assertNotNull("Library is an item", tagged(pick, "option:library"))
        tagged(pick, "option:want_to_read")!!.performClick()
        assertFalse("the page stays for more", pick.isFinishing)
        assertEquals("up_next\nwant_to_read", SettingsStore.get(app, "sleep_from"))
        tagged(pick, "option:discover")!!.performClick()
        assertEquals("up_next\nwant_to_read\ndiscover", SettingsStore.get(app, "sleep_from"))
        assertTrue("sent to KOReader, per key", SettingsStore.pending(app, "sleep_from"))
        val wire = SettingsSync.valuesJson(mapOf("sleep_from" to SettingEntry(SettingsStore.get(app, "sleep_from"), 1L)))
        assertTrue("the set travels as one value", wire.contains("up_next\\nwant_to_read\\ndiscover"))
        tagged(pick, "option:up_next")!!.performClick()
        assertEquals("unticked", "want_to_read\ndiscover", SettingsStore.get(app, "sleep_from"))
        tagged(pick, "option:library")!!.performClick()
        assertEquals("Library alone", "library", SettingsStore.get(app, "sleep_from"))
        assertEquals("Whole library", SettingsUi.valueLabel(schema.byKey.getValue("sleep_from"), "library"))
        assertEquals("Want to read, Discover", SettingsUi.valueLabel(schema.byKey.getValue("sleep_from"), "want_to_read\ndiscover"))

        val lo = open<LeaveOutActivity>()
        assertNull("Whole library is only a Pick from choice", tagged(lo, "pick:library"))
    }

    @Test
    fun aSearchHitOpensItsSectionAtTheRow() {
        SettingsStore.set(RuntimeEnvironment.getApplication(), "sync_mode", "custom", "test")
        val a = section("sync", focus = "sync_on_wake")
        assertNotNull(tagged(a, "key:sync_on_wake")!!.foreground)
    }

    @Test
    fun launcherButtonOpensSettings() {
        val a = open<LauncherActivity>()
        val b = all(a.window.decorView).filterIsInstance<TextView>().first { it.text.toString().contains("Settings") }
        val tile = b.parent as View
        assertTrue("the whole Settings tile is a tap target", tile.hasOnClickListeners())
        tile.performClick()
        assertEquals(SettingsActivity::class.java.name, shadowOf(a).nextStartedActivity.component?.className)
        assertNotNull("status moved to the launcher page", tagged(a, "status:service"))
    }
}
