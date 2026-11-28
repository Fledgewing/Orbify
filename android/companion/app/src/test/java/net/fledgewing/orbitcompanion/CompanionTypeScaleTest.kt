// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

import android.app.Activity
import android.text.Spanned
import android.text.style.RelativeSizeSpan
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import java.io.File
import java.lang.reflect.Modifier
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/** A screen may scroll; its Activity context must never reduce the shared body floor. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w749dp-h998dp-port-xxhdpi")
class CompanionTypeScaleTest {
    @Before fun setup() {
        SettingsStore.useSchema(SettingsSchema.parse(File("../../../shared/settings/schema.json").readText()))
        Prefs(RuntimeEnvironment.getApplication()).mode = OrbitMode.FULL
        SettingsPage.forceLocked = false
    }
    @After fun cleanup() { SettingsPage.forceLocked = null }

    private fun minimumPx(a: Activity): Float {
        val dm = a.resources.displayMetrics
        // Deliberately independent of textSize(): an Activity-specific multiplier must fail.
        val widthScale = ((dm.widthPixels / dm.density) / 749f).coerceIn(0.75f, 1.5f)
        return CompanionStyle.MIN_BODY * widthScale * dm.scaledDensity
    }

    @Test fun everyDeclaredCompanionScreenHonorsTheSharedMinimum() {
        val manifest = DocumentBuilderFactory.newInstance().newDocumentBuilder()
            .parse(File("src/main/AndroidManifest.xml"))
        val activities = manifest.getElementsByTagName("activity")
        var checked = 0
        val neutral = Robolectric.buildActivity(Activity::class.java).get()
        for (i in 0 until activities.length) {
            val name = activities.item(i).attributes.getNamedItem("android:name").nodeValue
            val type = Class.forName(if (name.startsWith(".")) "net.fledgewing.orbitcompanion$name" else name)
            if (!EinkActivity::class.java.isAssignableFrom(type) || Modifier.isAbstract(type.modifiers)) continue
            // Attach the real Activity context without executing launch/permission/routing actions.
            val a = Robolectric.buildActivity(type.asSubclass(Activity::class.java)).get()
            for (requested in listOf(8f, 12f, 16f, 20f, 24f, 28f, CompanionStyle.TITLE, CompanionStyle.LABEL)) {
                val body = Ui.text(a, "Readable companion body", requested)
                assertTrue("${type.simpleName}: $requested sp request rendered below the shared minimum",
                    body.textSize >= minimumPx(a) - 0.5f)
                assertEquals("${type.simpleName}: an Activity changed the shared role's size",
                    Ui.text(neutral, "Neutral body", requested).textSize, body.textSize, 0.5f)
            }
            assertTrue("${type.simpleName}: numeric/text input fell below the minimum", Ui.input(a).textSize >= minimumPx(a) - 0.5f)
            assertTrue("${type.simpleName}: checkbox label fell below the minimum", Ui.checkBox(a, "Readable option").textSize >= minimumPx(a) - 0.5f)
            checked++
        }
        assertTrue("exercise the manifest, not an empty or handpicked screen list", checked >= 20)
    }

    @Test fun newScreensCannotBypassTheSharedTextFactories() {
        val dir = File("src/main/java/net/fledgewing/orbitcompanion")
        val directView = Regex("\\b(?:TextView|EditText|CheckBox)\\s*\\(")
        for (file in dir.walkTopDown().filter { it.isFile && it.extension == "kt" && it != File(dir, "Ui.kt") }) {
            assertTrue("${file.name}: construct body text through Ui's factories", !directView.containsMatchIn(file.readText()))
            // SleepCanvas paints a sleep image, not an Android TextView screen.
            if (file != File(dir, "SleepCanvas.kt")) file.readLines().forEach { line ->
                if (Regex("(?:textSize\\s*=|setTextSize\\s*\\()").containsMatchIn(line)) {
                    assertTrue("${file.name}: raw text size bypasses the shared floor", line.contains("CompanionStyle.textSize"))
                }
            }
        }
    }

    private fun verifyTree(a: Activity) {
        var checked = 0
        fun visit(v: View) {
            if (v is HeaderBar) {
                val title = v.getChildAt(0) as TextView
                assertEquals("${a.javaClass.simpleName}: page title does not use the common title role",
                    minimumPx(a) * CompanionStyle.TITLE / CompanionStyle.MIN_BODY, title.textSize, 0.5f)
            }
            if (v is TextView && (v.text.isNotEmpty() || !v.hint.isNullOrEmpty())) {
                assertTrue("${a.javaClass.simpleName}: '${v.text.toString().ifEmpty { v.hint?.toString().orEmpty() }}' is too small",
                    v.textSize >= minimumPx(a) - 0.5f)
                (v.text as? Spanned)?.let { text ->
                    for (span in text.getSpans(0, text.length, RelativeSizeSpan::class.java)) {
                        assertTrue("${a.javaClass.simpleName}: subtitle span is too small",
                            v.textSize * span.sizeChange >= minimumPx(a) - 0.5f)
                    }
                }
                checked++
            }
            if (v is ViewGroup) (0 until v.childCount).forEach { visit(v.getChildAt(it)) }
        }
        visit(a.findViewById(android.R.id.content))
        assertTrue("the screen must actually draw text", checked > 0)
    }

    @Test fun launcherSubtitlesKeepTheMinimumForBothTileSizes() {
        val app = RuntimeEnvironment.getApplication()
        val prefs = Prefs(app)
        val previous = prefs.homeApp
        try {
            for (choice in listOf(HomeApp.KOREADER_LIBRARY, app.packageName)) {
                prefs.homeApp = choice
                val launcher = Robolectric.buildActivity(LauncherActivity::class.java).setup()
                verifyTree(launcher.get())
                launcher.pause().stop().destroy()
            }
        } finally { prefs.homeApp = previous }
    }

    @Test fun renderedSettingsSectionsControlsAndLockedViewStayAboveMinimum() {
        val top = Robolectric.buildActivity(SettingsActivity::class.java).setup()
        verifyTree(top.get())
        top.pause().stop().destroy()
        for (section in listOf("reading", "sync", "library", "sleep", "buttons", "kids", "setup", "updates")) {
            val app = RuntimeEnvironment.getApplication()
            val intent = SettingsPage.section(app, section).setClass(app, SettingsSectionActivity::class.java)
            val controller = Robolectric.buildActivity(SettingsSectionActivity::class.java, intent).setup()
            verifyTree(controller.get())
            controller.pause().stop().destroy()
        }
        SettingsPage.forceLocked = true
        val locked = Robolectric.buildActivity(SettingsActivity::class.java).setup()
        verifyTree(locked.get())
        locked.pause().stop().destroy()
    }
}
