package net.fledgewing.orbitcompanion.server.bookorbit

import net.fledgewing.orbitcompanion.*

import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/**
 * "Nothing interrupts reading" guard (CLAUDE.md product principles): every `notify(` and
 * `startActivity(` call site in the app is listed here, gated by Reading or exempt with a reason.
 * A new call site fails this test until it goes through Reading.show (or is user-initiated) and
 * is added below. A listed site that disappears fails it too, so the list stays true.
 */
class ReadingGuardTest {
    /** [needle]: text on the call's line; [count]: how many lines of [file] carry it. */
    private data class Site(val file: String, val needle: String, val count: Int, val why: String)

    private val allowed = listOf(
        // Gated by Reading.show (held while reading, posted at the next moment nobody reads).
        Site("Attention.kt", "nm.notify(ID,", 1, "setup reminder: posted only from Reading.show(KEY_SETUP); re-evaluated when held"),
        Site("Updater.kt", "nm.notify(ID_UPDATE", 1, "update ready: posted only from Reading.show(KEY_UPDATE); dropped once installed"),
        Site("OrbitService.kt", "notify(ID_TAILSCALE_ALERT", 1, "Tailscale alert: posted only from Reading.show(KEY_TAILSCALE); dropped when the VPN comes up"),
        Site("OrbitKeys.kt", "nm.notify(NOTE_ID", 1, "keyboard note: Reading.show(KEY_KEYBOARD), or at once when the user focused a text field"),
        Site("Installers.kt", "app.startActivity(confirm", 1, "KOReader install prompt: inside Reading.show(installKey)"),
        // Exempt: never pops up, or started by the user.
        Site("ReaderActionActivity.kt", "startActivityForResult(next,", 1, "foreground bridge only after a reader button: Android/security/recovery remains visible and no helper is enabled"),
        Site("Battery.kt", "startActivityForResult(i,", 2, "user requested battery export/document picker"),
        Site("DeviceSettings.kt", "ctx.startActivity(Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS", 1, "trusted plugin command: user chose Sleep after in an explicitly opened Settings menu; never automatic"),
        Site("OrbitService.kt", "notify(ID_STATUS", 1, "the ongoing foreground-service status: IMPORTANCE_LOW, setOnlyAlertOnce, never pops up"),
        Site("Updater.kt", "ctx.startActivity(confirm)", 1, "install prompt only when interactive: the user tapped Check for updates"),
        Site("Core.kt", "ctx.startActivity(i)", 2, "HomeTarget/Koreader starts: Home press, Setup taps, RELAUNCH; restarts follow UpdateFlow.restart (manual or screen-off only)"),
        Site("Attention.kt", "a.startActivity(Intent(a, AttentionActivity", 1, "prompt after a change the user made in a companion page"),
        Site("ClickerService.kt", "PinActivity.Mode.GUARD", 1, "the PIN keypad over a guarded app the user just opened"),
        Site("Pin.kt", "PinActivity.Mode.UNLOCK", 1, "Pin.run: the user tapped a PIN-guarded action"),
        Site("Pin.kt", "CATEGORY_HOME", 1, "the user cancelled the guard keypad: back Home"),
        Site("OrbitKeys.kt", "ACTION_INPUT_METHOD_SETTINGS", 1, "the user tapped the keyboard notification's Switch keyboard"),
        Site("UpdateReturn.kt", "ctx.startActivities(list", 1, "back to the pages where the user tapped Update, once the update replaced the app"),
        Site("Mode.kt", "SetupActivity::class.java", 1,"the user switched mode on the Mode page"),
        Site("Ui.kt", "PinActivity.Mode.UNLOCK", 1, "a PIN-guarded page the user opened"),
        Site("Ui.kt", "override fun startActivity(", 1, "EinkActivity's own override (no animation)"),
        Site("Ui.kt", "super.startActivity(intent, options)", 1, "EinkActivity's own override (no animation)"),
        Site("Ui.kt", "        startActivity(intent)", 1, "tryStart: Setup Fix and Settings taps"),
        Site("Launcher.kt", "startActivity(i)", 1, "the launcher page, shown by the Home activity (Home press or KOReader gone)"),
        Site("Launcher.kt", "startActivity(Intent(this,", 2, "launcher page buttons"),
        Site("Clicker.kt", "startActivity(", 4, "clicker pages: the user's taps and key captures"),
        Site("Pages.kt", "startActivity(Intent(this,", 7, "companion pages: the user's taps, or opened from a page the user opened"),
        Site("Pages.kt", "startActivity(SettingsPage.section(this, \"sync\", \"helper_wifi\"))", 1, "explicit reader helper-settings link; never background work"),
        Site("Pages.kt", "a.startActivity(SettingsPage.section(a, \"sync\")", 1, "Setup (Add-on): the user tapped Turn on for a helper"),
        Site("Pages.kt", "a.startActivity(", 5, "status and info (StatusPanel, the launcher page): the user's taps"),
        Site("SettingsPages.kt", "startActivity(", 19, "Settings pages: the user's taps"),
        Site("CommandProvider.kt", "ctx.startActivity(Intent(ctx, AccountActivity", 1, "trusted plugin call: user tapped Sign in to your server"),
        Site("AboutActivity.kt", "startActivity(", 2, "About: the user tapped the project link or open-source licenses"),
        Site("Attention.kt", "startActivity(Intent(this, SetupBatteryActivity", 1, "the prompt: the user tapped Help on the Battery row"),
        Site("ChecklistUi.kt", "ctx.startActivity(Intent(ctx, SetupDetailsActivity", 1, "Setup: the user tapped Details"),
        Site("BookOrbitCovers.kt", "a.startActivity(Intent(a, SleepScreenActivity", 1, "Setup: the user tapped Sign in again on the sharp covers row"),
    )

    private val call = Regex("""(^|[^A-Za-z0-9_])(notify|startActivity|startActivities|startActivityForResult)\(""")

    private fun sources(): File {
        val rel = "src/main/java/net/fledgewing/orbitcompanion"
        return listOf(File(rel), File("app/$rel")).firstOrNull { it.isDirectory } ?: error("sources not found from ${File(".").absolutePath}")
    }

    /**
     * The sleep screen's dream (docs/design/lock-screen.md) is started only by the system, at sleep:
     * the manifest protects it with BIND_DREAM_SERVICE, and it never notifies or starts anything.
     */
    @Test
    fun sleepDreamIsSystemStartedOnly() {
        val src = File(sources(), "SleepDream.kt").readText()
        assertTrue("SleepDream must not notify or start activities", !call.containsMatchIn(src))
        val manifest = listOf(File("src/main/AndroidManifest.xml"), File("app/src/main/AndroidManifest.xml")).first { it.isFile }.readText()
        val block = manifest.substringAfter("android:name=\".SleepDream\"").substringBefore("</service>")
        assertTrue("SleepDream needs BIND_DREAM_SERVICE", block.contains("android:permission=\"android.permission.BIND_DREAM_SERVICE\""))
    }

    @Test
    fun everyNotifyAndStartActivityIsGatedOrExempt() {
        val counts = HashMap<Site, Int>()
        val unknown = mutableListOf<String>()
        sources().walkTopDown().filter { it.isFile && it.extension == "kt" }.sortedBy { it.path }.forEach { f ->
            f.readLines().forEachIndexed { i, line ->
                val t = line.trim()
                if (t.startsWith("//") || t.startsWith("*") || t.startsWith("/*") || !call.containsMatchIn(line)) return@forEachIndexed
                val site = allowed.firstOrNull { it.file == f.name && line.contains(it.needle) }
                if (site == null) unknown += "${f.name}:${i + 1}: $t" else counts[site] = (counts[site] ?: 0) + 1
            }
        }
        if (unknown.isNotEmpty()) {
            fail("New notify/startActivity call sites: route them through Reading.show (nothing interrupts reading) or list them here with why they are exempt:\n" + unknown.joinToString("\n"))
        }
        val wrong = allowed.filter { (counts[it] ?: 0) != it.count }
            .map { "${it.file} \"${it.needle}\": expected ${it.count}, found ${counts[it] ?: 0} (${it.why})" }
        assertTrue("Allow-list out of date:\n" + wrong.joinToString("\n"), wrong.isEmpty())
    }
}
