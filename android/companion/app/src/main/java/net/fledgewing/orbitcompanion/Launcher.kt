package net.fledgewing.orbitcompanion

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView

/**
 * The HOME activity. Translucent and empty: it never draws, it only decides.
 * Every Home press and every boot starts KOReader with "home"; a second press within 2 s, or a
 * KOReader that is missing or won't start, shows the launcher page instead (HomeDecider).
 */
class HomeActivity : Activity() {
    companion object {
        /** Process-wide, so presses are paired across activity re-creation. */
        val decider = HomeDecider()
    }

    private var pressPending = false
    private var startOnScreenOn = false

    private val screenOnReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            if (startOnScreenOn) {
                startOnScreenOn = false
                OLog.i("home: screen on, starting the deferred KOReader")
                decide(press = false)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setWindowAnimations(0)
        OrbitService.start(this)
        registerReceiver(screenOnReceiver, IntentFilter(Intent.ACTION_SCREEN_ON))
        pressPending = true // boot, or a Home press that found no home task
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pressPending = true
    }

    override fun onResume() {
        super.onResume()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
        val press = pressPending
        pressPending = false
        if (!Net.screenOn(this)) {
            // KOReader went away with the screen off (some firmwares force-stop the foreground app
            // a while after the power button). Start it on the next wake, not now: a start now
            // could be stopped again.
            startOnScreenOn = true
            OLog.i("home: ${if (press) "press" else "uncovered"} with the screen off, KOReader starts on wake")
            return
        }
        decide(press)
    }

    private fun decide(press: Boolean) {
        // Just after an update started from one of our pages: that page, not KOReader (UpdateReturn).
        UpdateReturn.forHome()?.let { if (UpdateReturn.open(this, it, "home after the update", reuse = true)) return }
        // Home is navigation, including for offline readers without a server account.
        // Setup/sign-in remain available from Home and the explicit companion pages.
        if (press) Attention.evaluate(this,"home press",notify=false)
        // A transient task closing must not cover a companion page the user opened.
        if (!press && EinkActivity.pageResumed()) return
        val prefs = Prefs(this)
        val choice = prefs.homeApp
        val other = HomeApp.isApp(choice)
        val opensApp = !HomeApp.isLauncher(choice)
        // Disabled (e.g. a vendor launcher's app freeze) counts as unusable: starting it would throw.
        val problem = if (other) HomeTarget.problem(this, choice) else Koreader.problem(this)
        val installed = problem == null
        val now = SystemClock.elapsedRealtime()
        val action = if (press) {
            decider.onHomePress(now, installed, opensApp)
        } else {
            decider.onUncovered(now, installed, opensApp)
        }
        val why = when {
            problem != null -> problem
            !opensApp -> null
            press -> "Home pressed twice."
            else -> "${HomeTarget.name(this)} closed straight after starting."
        }
        OLog.i("home ${if (press) "press" else "uncovered"}: $action${if (problem != null) " ($problem)" else ""}")
        // A patch waiting to load and no book open: this Home press restarts KOReader instead.
        if (action == HomeAction.START_KOREADER && !HomeApp.isApp(choice) && PatchInstaller.follow(this, "home press")) return
        if (action == HomeAction.START_KOREADER) {
            // The chosen Home action is explicit on both presses and recovery: library home
            // sends "home"; Back to my book sends "home_smart" (HomePlan decides).
            // Another "Home opens" app: just bring it to the front (HomeApp.launch).
            val l = HomeApp.launch(choice, press, prefs.homeButton, EinkActivity.companionPageInFront())
            val reason = if (press) "home press" else "home uncovered"
            val started = if (l.pkg != null) {
                HomeTarget.start(this, l.pkg, reason)
            } else {
                OLog.i("home: ${prefs.homeButton.key} -> command ${l.command ?: "-"}${if (l.from != null) " from ${l.from}" else ""}")
                Koreader.start(this, reason, l.command, l.from)
            }
            if (started) return
            decider.startFailed()
            showLauncher("${HomeTarget.name(this)} didn't start.")
        } else {
            showLauncher(why)
        }
    }

    private fun showLauncher(why: String?) {
        val i = Intent(this, LauncherActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
        if (why != null) i.putExtra("why", why)
        startActivity(i)
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // A launcher ignores Back.
    }

    override fun onDestroy() {
        unregisterReceiver(screenOnReceiver)
        super.onDestroy()
    }
}

/** Mockup 1: the escape-hatch launcher page. */
open class LauncherActivity : EinkActivity() {
    protected open val rendersOnResume = true
    private var why: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        why = intent.getStringExtra("why")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        why = intent.getStringExtra("why")
    }

    override fun onResume() {
        super.onResume()
        // Back from Android's install prompt (the Install row is here now): "Android is checking…".
        Updater.onPageResumed(this)
        // Unfrozen since: drop the stale message.
        if (why == Vendor.disabledMessage(this, "KOReader") && Koreader.state(this) != AppState.FROZEN) why = null
        if (rendersOnResume) render()
    }

    protected open fun render() {
        val root = page()
        root.addView(Ui.header(this, "BookSync"))
        val choice = Prefs(this).homeApp
        if (HomeApp.isApp(choice)) {
            // "Home opens" another app: it is the big first tile; KOReader stays a tile below.
            val name = HomeTarget.label(this, choice)
            root.addView(Ui.button(this, "Open $name", solid = true, heightDp = 120, sp = 26f) {
                if (HomeTarget.start(this, choice, "launcher button")) {
                    HomeActivity.decider.startedByHand(SystemClock.elapsedRealtime())
                } else {
                    why = HomeTarget.problem(this, choice) ?: "$name didn't start."
                    render()
                }
            })
            root.addView(Ui.gap(this, 8))
        }
        val koFirst = !HomeApp.isApp(choice)
        val open = Ui.button(this, "Open KOReader\n", solid = koFirst, heightDp = if (koFirst) CompanionStyle.HERO_HEIGHT else 120, sp = if (koFirst) CompanionStyle.HERO_TYPE else CompanionStyle.TILE_TYPE) {
            if (Koreader.goHome(this, "launcher button")) {
                HomeActivity.decider.startedByHand(SystemClock.elapsedRealtime())
            } else {
                why = Koreader.problem(this) ?: "KOReader didn't start."
                render()
            }
        }
        open.text = android.text.SpannableStringBuilder().apply {
            append("Open KOReader\n")
            val s = length
            append(if (Prefs(this@LauncherActivity).homeButton == HomeButton.SMART) "back to your book" else "opens on library home")
            setSpan(android.text.style.RelativeSizeSpan(CompanionStyle.subtitleScale(if (koFirst) CompanionStyle.HERO_TYPE else CompanionStyle.TILE_TYPE)), s, length, 0)
            setSpan(android.text.style.StyleSpan(android.graphics.Typeface.NORMAL), s, length, 0)
        }
        root.addView(open)
        why?.let { root.addView(Ui.text(this, it, 18f, color = Ui.MID).apply { setPadding(0, Ui.dp(this@LauncherActivity, 8), 0, 0) }) }
        if (Koreader.state(this) == AppState.FROZEN) {
            root.addView(Ui.gap(this, 8))
            root.addView(
                Ui.button(this, "Re-enable KOReader") {
                    tryStart(Vendor.reenablePage(this, Koreader.PKG), "re-enable page")
                },
            )
        }
        Attention.evaluate(this, "launcher", notify = false)
        root.addView(Ui.gap(this, 12))
        root.addView(
            Ui.weightRow(
                this,
                Ui.launcherTile(this, "⋯", "Other apps") { startActivity(Intent(this, AppsActivity::class.java)) },
                Ui.launcherTile(this, "⚙", "Settings") { startActivity(Intent(this, SettingsActivity::class.java)) },
            ),
        )
        root.addView(Ui.gap(this, 12))
        // Setup right under the two buttons (M8C feedback: the main view fits on one screen, and
        // "1 thing needs you" is the one line that matters); the old "N setup steps need you"
        // banner said the same and is gone.
        StatusPanel.setupCard(this, root)
        root.addView(Ui.gap(this, 8))
        // Wi-Fi by hand: on here is the user's, so "Just in time" leaves it on until they turn it off.
        val wifiOn = Net.wifiEnabled(this)
        root.addView(Ui.row(this, "Wi-Fi", if (wifiOn) "on · ${Prefs(this).wifiOwner.key}" else "off", Ui.toggle(this, wifiOn), onClick = {
            if (wifiOn) {
                Net.setWifi(this, false, "launcher Wi-Fi tile")
            } else {
                Net.setWifi(this, true, "launcher Wi-Fi tile", WifiOwner.MANUAL)
            }
            android.os.Handler(mainLooper).postDelayed({ if (!isFinishing) render() }, 800)
        }, compact = true))
        // Status and info, moved here from the old "Companion" page (companion-settings §5.9).
        StatusPanel.draw(this, root, wifiRow = false, setup = false) { if (!isFinishing) render() }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // The launcher page is the bottom of the Home task: Back does nothing.
    }
}

/**
 * Mockup 2: pinned tiles, then all apps A–Z, paged (no scrolling). Hold a row to pin or unpin;
 * hold a tile to unpin. Also opened by the patch (SHOW_APPS).
 */
class AppsActivity : EinkActivity() {
    data class App(val label: String, val component: ComponentName, val frozen: Boolean = false)

    companion object {
        const val MAX_PINS = 6

        /** Fixed "Android Settings" tile: not a real component; launch() opens Settings.ACTION_SETTINGS. */
        val SETTINGS_TILE = ComponentName("android.settings", "ACTION_SETTINGS")
    }

    private lateinit var prefs: Prefs
    internal var apps: List<App> = emptyList()
        private set
    private var listening = false

    /** Any package change while the page shows rebuilds the list, so it is never a stale copy. */
    private val packages = AppList.receiver {
        if (!isFinishing) {
            apps = loadApps()
            render()
        }
    }
    private var pageIndex = 0
    private var perPage = 0
    private var note: String = "hold to pin"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefs = Prefs(this)
    }

    override fun onResume() {
        super.onResume()
        if (!listening) {
            AppList.register(this, packages)
            listening = true
        }
        apps = loadApps()
        if (prefs.pins == null) prefs.pins = defaultPins()
        seedSettingsPin()
        render()
    }

    override fun onPause() {
        super.onPause()
        if (listening) {
            unregisterReceiver(packages)
            listening = false
        }
    }

    private fun loadApps(): List<App> {
        // Frozen apps included, each app kept even when its label fails (AppList).
        val list = AppList.load(this).map { App(it.label, ComponentName(it.pkg, it.cls), it.frozen) }.toMutableList()
        // "<Vendor> home" from the vendor profile, if this device has one (Vendor.kt).
        Vendor.homeTile(this)?.let { (label, component) -> list.add(App(label, component)) }
        list.add(App("Android Settings", SETTINGS_TILE))
        return list.distinctBy { it.component }.sortedBy { it.label.lowercase() }
    }

    private fun defaultPins(): List<String> {
        val tailscale = apps.firstOrNull { it.component.packageName == Net.TAILSCALE_PKG }?.component
        val vendorHome = Vendor.homeTile(this)?.second?.let { home -> apps.firstOrNull { it.component == home }?.component }
        return listOfNotNull(tailscale, SETTINGS_TILE, vendorHome).map { it.flattenToString() }
    }

    /** Once per install: pins made before the Settings tile existed get it too. Unpinning sticks. */
    private fun seedSettingsPin() {
        if (prefs.settingsPinSeeded) return
        prefs.settingsPinSeeded = true
        val key = SETTINGS_TILE.flattenToString()
        val pins = prefs.pins.orEmpty()
        if (key !in pins && pins.size < MAX_PINS) prefs.pins = pins + key
    }

    private fun pinned(): List<App> {
        val byKey = apps.associateBy { it.component.flattenToString() }
        return prefs.pins.orEmpty().mapNotNull { byKey[it] }
    }

    private fun launch(app: App) {
        if (app.component == SETTINGS_TILE) {
            Pin.run(this) { tryStart(Intent(android.provider.Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), "Android Settings") }
            return
        }
        if (app.frozen) {
            // A disabled app can't start: open the page that unfreezes it.
            note = "${app.label} is frozen"
            tryStart(Vendor.reenablePage(this, app.component.packageName), "re-enable page for ${app.component.packageName}")
            return
        }
        val i = Intent(Intent.ACTION_MAIN).setComponent(app.component).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (app.component != Vendor.homeTile(this)?.second) i.addCategory(Intent.CATEGORY_LAUNCHER)
        tryStart(i, "app ${app.component.flattenToShortString()}")
    }

    private fun togglePin(app: App) {
        val key = app.component.flattenToString()
        val pins = prefs.pins.orEmpty().toMutableList()
        note = when {
            pins.remove(key) -> "Unpinned ${app.label}"
            pins.size >= MAX_PINS -> "Six pinned: hold a tile to unpin one"
            else -> {
                pins.add(key)
                "Pinned ${app.label}"
            }
        }
        prefs.pins = pins
        render()
    }

    private fun render() {
        // Paged by the height it gets (no scrolling): measured below.
        val root = page(scroll = false)
        root.addView(Ui.header(this, "Other apps", "‹ Back") { finish() })

        // Pinned tiles, three per row.
        val tiles = pinned()
        tiles.chunked(3).forEach { rowApps ->
            val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            for (i in 0 until 3) {
                val lp = LinearLayout.LayoutParams(0, Ui.dp(this, 110), 1f).apply {
                    if (i > 0) marginStart = Ui.dp(this@AppsActivity, 10)
                }
                val app = rowApps.getOrNull(i)
                row.addView(if (app == null) View(this) else tile(app), lp)
            }
            root.addView(row)
            root.addView(Ui.gap(this, 10))
        }

        val label = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, Ui.dp(this@AppsActivity, 8), 0, Ui.dp(this@AppsActivity, 4))
            addView(Ui.text(this@AppsActivity, "ALL APPS · A–Z", 16f, bold = true), LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(Ui.text(this@AppsActivity, note, 16f, color = Ui.MID))
        }
        root.addView(label)

        val list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.addView(list, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        val pager = Ui.text(this, "", CompanionStyle.CAPTION)
        val prev = Ui.button(this, "‹ prev", heightDp = 72) { turn(-1) }
        val next = Ui.button(this, "next ›", heightDp = 72) { turn(+1) }
        pager.gravity = Gravity.CENTER
        pager.setTextColor(Ui.INK)
        val footer = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(prev, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(pager, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(next, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        }
        root.addView(footer)

        // The page size depends on the space left, known after layout.
        list.addOnLayoutChangeListener { v, _, top, _, bottom, _, oldTop, _, oldBottom ->
            if (bottom - top != oldBottom - oldTop || perPage == 0) {
                perPage = maxOf(1, (bottom - top) / Ui.dp(this, Ui.ROW_DP + 4))
                v.post { fillPage(list, pager) }
            }
        }
        if (perPage > 0) fillPage(list, pager)
    }

    private fun pageCount() = maxOf(1, (apps.size + perPage - 1) / maxOf(1, perPage))

    private fun turn(delta: Int) {
        val n = pageCount()
        pageIndex = (pageIndex + delta + n) % n
        render()
    }

    private fun fillPage(list: LinearLayout, pager: TextView) {
        list.removeAllViews()
        val n = pageCount()
        pageIndex = pageIndex.coerceIn(0, n - 1)
        val pins = prefs.pins.orEmpty().toSet()
        apps.drop(pageIndex * perPage).take(perPage).forEach { app ->
            val pinned = app.component.flattenToString() in pins
            list.addView(
                Ui.row(
                    this, app.label,
                    left = Ui.letter(this, app.label),
                    right = listOfNotNull("frozen".takeIf { app.frozen }, "pinned".takeIf { pinned })
                        .takeIf { it.isNotEmpty() }?.let { Ui.value(this, it.joinToString(" · "), bold = false) },
                    onClick = { launch(app) },
                    onLong = { togglePin(app) },
                ),
            )
        }
        pager.text = "page ${pageIndex + 1} of $n"
        // perPage assumes rows of ROW_DP; a taller row (a wrapped label, a large system font) would
        // push the page's last app below the list's edge, clipped out of sight. Fewer per page then.
        list.post {
            val fit = AppListLogic.fits((0 until list.childCount).map { list.getChildAt(it).bottom }, list.height)
            if (list.height > 0 && fit < list.childCount) {
                OLog.d("apps page: $fit of ${list.childCount} rows fit, $perPage -> $fit per page")
                perPage = fit
                fillPage(list, pager)
            }
        }
    }

    private fun tile(app: App): View = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
        background = Ui.pressable(Ui.box(this@AppsActivity, Ui.PAPER), Ui.box(this@AppsActivity, Ui.PRESSED))
        addView(Ui.letter(this@AppsActivity, app.label).apply {
            (layoutParams as LinearLayout.LayoutParams).marginEnd = 0
        })
        addView(Ui.text(this@AppsActivity, app.label, 16f).apply {
            gravity = Gravity.CENTER
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        })
        Ui.clickable(this, { launch(app) }, { togglePin(app) })
    }
}
