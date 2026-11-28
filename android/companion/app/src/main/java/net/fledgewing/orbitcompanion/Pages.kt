package net.fledgewing.orbitcompanion

import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.view.Gravity
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView

/** Lines shared by the launcher page and the status page. */
object Status {
    fun networkLine(ctx: Context): String = when {
        !Net.wifiEnabled(ctx) -> "Wi-Fi off"
        !Net.wifiConnected(ctx) -> "Wi-Fi connecting"
        Net.vpnUp(ctx) -> "Wi-Fi + Tailscale up"
        else -> "Wi-Fi up · Tailscale off"
    }

    fun lastSleepSync(ctx: Context): String {
        val p = Prefs(ctx)
        if (p.lastSleepSyncAt == 0L) return "none yet"
        val s = p.lastSleepSyncSeconds.ifEmpty { "?" }
        return "${Ui.clock(ctx, p.lastSleepSyncAt)} · ${if (p.lastSleepSyncOk) "done" else "failed"}, $s s"
    }

    fun lastNetReady(ctx: Context): String {
        val p = Prefs(ctx)
        if (p.lastNetReadyAt == 0L) return "none yet"
        return "${Ui.clock(ctx, p.lastNetReadyAt)} · ${Ui.secs(p.lastNetReadyMs)}"
    }

    fun wifiTimer(ctx: Context): String {
        val p = Prefs(ctx)
        val now = System.currentTimeMillis()
        return when {
            p.wifiOffDeadline > now && Net.wifiEnabled(ctx) -> "in ${WifiPolicy.minutesLeft(now, p.wifiOffDeadline)} min"
            p.wifiAfterSleep == WifiAfterSleep.KEEP_ON -> "never (Keep on)"
            else -> "no timer"
        }
    }
}

/**
 * Times Wi-Fi + Tailscale. Polls every 250 ms and reports once at the end (one e-ink redraw).
 * [offFirst]: the setup checklist's Wi-Fi off/on test, which also records whether Android
 * showed a prompt (a refused call, a state that never changed, or our window losing focus).
 */
class NetTest(private val ctx: Context, private val offFirst: Boolean, private val done: (Boolean, String) -> Unit) {
    private val h = Handler(Looper.getMainLooper())
    private var t0 = 0L
    private var onAt = 0L
    private var wifiMs = -1L
    private var phase = 0
    private var refused = false
    private var wasOn = true
    private var restored: Boolean? = null
    var focusLost = false
    var running = false
        private set

    fun start() {
        running = true
        t0 = SystemClock.elapsedRealtime()
        OLog.i("${if (offFirst) "Wi-Fi off/on test" else "network test"} started")
        if (offFirst) {
            // Leave Wi-Fi as found (WifiTestPlan): on -> off, on; off -> on (timed), off.
            wasOn = Net.wifiEnabled(ctx)
            OLog.i("Wi-Fi test: steps ${WifiTestPlan.steps(wasOn)} (Wi-Fi was ${if (wasOn) "on" else "off"})")
            if (wasOn) {
                refused = !Net.setWifi(ctx, false, "setup Wi-Fi test")
                phase = 0
            } else {
                wifiOn()
            }
        } else {
            wifiOn()
            Net.connectTailscale(ctx, "network test")
        }
        h.postDelayed(::tick, 250)
    }

    private fun wifiOn() {
        phase = 1
        onAt = SystemClock.elapsedRealtime()
        if (!Net.wifiEnabled(ctx) && !Net.setWifi(ctx, true, if (offFirst) "setup Wi-Fi test" else "network test")) refused = true
    }

    private fun tick() {
        val now = SystemClock.elapsedRealtime()
        when (phase) {
            0 -> when {
                !Net.wifiEnabled(ctx) -> wifiOn()
                now - t0 > 10_000 -> return finish(false, "Wi-Fi didn't turn off")
            }
            1 -> when {
                Net.wifiConnected(ctx) -> {
                    wifiMs = now - onAt
                    if (offFirst) {
                        if (!wasOn) restored = Net.setWifi(ctx, false, "setup Wi-Fi test: restoring off")
                        return finish(true, "")
                    }
                    Net.connectTailscale(ctx, "network test, Wi-Fi up")
                    phase = 2
                }
                now - onAt > 45_000 -> return finish(false, "Wi-Fi didn't reconnect in 45 s")
            }
            2 -> when {
                Net.vpnUp(ctx) -> return finish(true, "")
                now - onAt > 30_000 -> return finish(false, "Tailscale didn't connect")
            }
        }
        h.postDelayed(::tick, 250)
    }

    private fun finish(ok: Boolean, problem: String) {
        running = false
        if (offFirst && !wasOn && restored == null && Net.wifiEnabled(ctx)) restored = Net.setWifi(ctx, false, "setup Wi-Fi test: restoring off")
        val prompt = refused || focusLost
        val total = SystemClock.elapsedRealtime() - t0
        val summary = if (offFirst) {
            val reconnect = if (wifiMs >= 0) "${if (wasOn) "reconnected" else "connected"} in ${Ui.secs(wifiMs)}" else problem
            val p = if (prompt) "Android prompted or refused" else "no prompt"
            val back = when (restored) {
                true -> " · turned back off (it was off)"
                false -> " · could not turn it back off"
                null -> if (!wasOn && wifiMs < 0) " · left off" else ""
            }
            "$reconnect · $p$back"
        } else {
            val parts = mutableListOf<String>()
            if (wifiMs >= 0) parts.add("Wi-Fi ${Ui.secs(wifiMs)}")
            if (ok) parts.add("Tailscale ${Ui.secs(SystemClock.elapsedRealtime() - onAt - wifiMs)}")
            if (problem.isNotEmpty()) parts.add(problem)
            parts.joinToString(" · ")
        }
        OLog.i("${if (offFirst) "Wi-Fi off/on test" else "network test"} ${if (ok) "passed" else "FAILED"} in $total ms: $summary (refused=$refused focusLost=$focusLost)")
        done(ok && !(offFirst && prompt), summary)
    }

    fun cancel() {
        h.removeCallbacksAndMessages(null)
        running = false
    }
}

/**
 * The app's icon, SHOW_STATUS and the notification's target. Full mode: the launcher page is the
 * status page (docs/design/companion-settings.md §5.9), so this runs the first-run choice and the
 * "Setup needs you" prompt, then renders the launcher page in its own task root. Add-on mode: this is the main page, the
 * same status and info (StatusPanel) under a Settings button.
 */
class StatusActivity : LauncherActivity() {
    override val rendersOnResume = false
    private var prompted = false

    override fun onNewIntent(next: Intent) {
        super.onNewIntent(next)
        intent = next
        openHelperLink()
    }

    private fun openHelperLink(): Boolean {
        if (intent.getStringExtra("booksync_page") == "helpers" && Mode.isAddon(this)) {
            intent.removeExtra("booksync_page")
            startActivity(SettingsPage.section(this, "sync", "helper_wifi"))
            finish()
            return true
        }
        return false
    }

    override fun onResume() {
        super.onResume()
        if (isFinishing || openHelperLink()) return
        OrbitService.start(this)
        // The first-run choice (docs/design/addon-mode.md §4.1): existing installs were set to
        // Full by the migration in OrbitService.start, so only a new install sees it.
        if (!prompted && Prefs(this).mode == null) {
            prompted = true
            startActivity(Intent(this, ModeActivity::class.java))
            return
        }
        // "Setup needs you": once per visit, only when a step needs the user or after an update.
        val prompt = !prompted && Attention.shouldPrompt(Attention.evaluate(this, "status page"), this)
        prompted = true
        // Keep the launcher entry as the visible task root. Finishing this root
        // after a redirect can uncover the HOME task, which starts KOReader again.
        if (prompt) startActivity(Intent(this, AttentionActivity::class.java))
        render()
    }

    override fun render() {
        if (Prefs(this).mode != OrbitMode.ADDON) return super.render()
        val root = page()
        root.addView(Ui.header(this, "BookSync Companion", "Settings") { startActivity(Intent(this, SettingsActivity::class.java)) })
        StatusPanel.draw(this, root, wifiRow = true) { if (!isFinishing) render() }
    }
}

/**
 * Status and info (docs/design/companion-settings.md §5.9): the launcher page in Full mode, the
 * main page in Add-on. What can be chosen lives in Settings; this only shows and installs.
 */
object StatusPanel {
    /** The Setup summary card (companion-checklist §3.8): "Setup: all set ✓" or "Setup: 1 thing needs you ›". */
    fun setupCard(a: EinkActivity, root: LinearLayout) {
        val items = Setup.items(a)
        root.addView(ChecklistUi.statusCard(a, Setup.summary(a, items), items) {
            a.startActivity(Intent(a, SetupActivity::class.java))
        }.apply { tag = "status:setup" })
    }

    /** [setup]: false where the page draws [setupCard] itself, higher up (the launcher page). */
    fun draw(a: EinkActivity, root: LinearLayout, wifiRow: Boolean, setup: Boolean = true, redraw: () -> Unit) {
        // After an update: a line to tap, never a notification of its own.
        WhatsNew.line(Attention.whatsNew(a).isNotEmpty(), BuildConfig.VERSION_NAME)?.let { t ->
            root.addView(Ui.row(a, t, onClick = { a.startActivity(Intent(a, AttentionActivity::class.java)) }).apply { tag = "status:whats_new" })
        }
        // A Full refresh saving for offline: its % (the same number the plugin's badge shows), redrawn
        // when it changes.
        Worker.progressLine()?.let { line ->
            root.addView(Ui.text(a, line, 17f).apply { tag = "status:offline" })
            fun watch() {
                root.postDelayed({ if (!a.isFinishing) { if (Worker.progressLine() != line) redraw() else watch() } }, 3_000)
            }
            watch()
        }
        Updater.readyToDownload(a)?.let { ready ->
            root.addView(Ui.row(a, "App version", "Update ready: v${ready.first}", Ui.button(a, "Download", heightDp = 56, sp = CompanionStyle.STATUS_TYPE) {
                Pin.run(a) { a.tryStart(ready.second, "BookSync download") }
            }).apply { tag = "status:download" })
        }
        // A background update is ready: "Install" any time here (the notification waits while reading).
        Updater.readyToInstall()?.let { ready ->
            root.addView(Ui.row(a, "App version", "Update ready: v${Version.parse(ready.first)?.display() ?: ready.first}", Ui.button(a, "Install", heightDp = 56, sp = CompanionStyle.STATUS_TYPE) {
                // Through the PIN keypad like the notification's tap (no PIN or unlocked: Android's prompt).
                a.startActivity(PinActivity.thenInstall(a, ready.second))
            }).apply { tag = "status:install" })
        }
        if (wifiRow) {
            val wifi = when {
                !Net.wifiEnabled(a) -> "Off"
                Net.wifiConnected(a) -> "On · connected"
                else -> "On · not connected"
            }
            root.addView(Ui.row(a, "Wi-Fi", right = Ui.value(a, wifi, sp = CompanionStyle.STATUS_TYPE), compact = true))
        }
        val ts = when (Net.appState(a, Net.TAILSCALE_PKG)) {
            AppState.MISSING -> "Not installed"
            AppState.FROZEN -> AppStates.disabledShort(Vendor.disablerLabel(a))
            else -> if (Net.vpnUp(a)) "Connected" else "Not connected"
        }
        root.addView(Ui.row(a, "Tailscale", right = Ui.value(a, ts, sp = CompanionStyle.STATUS_TYPE), compact = true).apply { tag = "status:tailscale" })
        root.addView(Ui.row(a, "Service", right = Ui.value(a, when {
            OrbitService.running -> "Running"
            !Mode.needsService(a) -> "Off (Add-on, no helper)"
            else -> "Starting"
        }, sp = CompanionStyle.STATUS_TYPE), compact = true).apply { tag = "status:service" })
        root.addView(Ui.row(a, "Screen-off permission", right = Ui.value(a, if (Net.adminActive(a)) "Granted" else "Not granted", sp = CompanionStyle.STATUS_TYPE), compact = true))
        root.addView(Ui.row(a, "Battery", "hours left, % per hour, by setting, history", Ui.value(a, "›"), onClick = {
            a.startActivity(Intent(a, BatteryActivity::class.java))
        }, compact = true))
        root.addView(Ui.gap(a, 8))
        val card = Ui.card(a)
        card.addView(Ui.row(a, "Network", right = Ui.value(a, Status.networkLine(a), sp = CompanionStyle.STATUS_TYPE), compact = true))
        card.addView(Ui.row(a, "Last sleep sync", null, Ui.value(a, Status.lastSleepSync(a), sp = CompanionStyle.STATUS_TYPE), compact = true))
        card.addView(Ui.row(a, "Last wake network ready in", right = Ui.value(a, Status.lastNetReady(a), sp = CompanionStyle.STATUS_TYPE), compact = true))
        card.addView(Ui.row(a, "Wi-Fi turns off", right = Ui.value(a, Status.wifiTimer(a), sp = CompanionStyle.STATUS_TYPE), compact = true))
        root.addView(card)
        // The same summary as the Setup page (docs/design/companion-checklist.md §3.8).
        if (setup) {
            root.addView(Ui.gap(a, 12))
            setupCard(a, root)
        }
        Vendor.disabledApps(a).takeIf { it.isNotEmpty() }?.let { frozen ->
            root.addView(Ui.text(a, frozen.joinToString(" ") { Vendor.disabledMessage(a, it) }, 18f, bold = true).apply {
                setPadding(0, Ui.dp(a, 10), 0, 0)
            })
        }
    }
}

/**
 * A Setup row. pending: fine but waiting on something outside the app (shown, never counted).
 * action: its one verb, null = no button. The label is a noun that never changes with the state;
 * detail is the state line (docs/design/companion-checklist.md §3.3).
 */
class Check(
    val label: String,
    val done: Boolean,
    val detail: String,
    val pending: Boolean = false,
    val action: String? = "Fix",
    /** Update follow-through (install this release's patch, restart KOReader): never behind the PIN. */
    val pinFree: Boolean = false,
    /** A tip, not a step (SetupTips): "Got it" hides it; never counted. */
    val advisory: Boolean = false,
    /** An optional row ("On: …" / "Without it: …"), never counted, walked or prompted. */
    val optional: Boolean = false,
    /** Stable id: stored skips and snoozes are keyed by it, never by the label (D17). */
    val id: String = SetupAttention.idOf(label),
    /** Its words in the group's one line when done. */
    val short: String = label,
    /** Shown, never counted (a test, Add-on's status lines). */
    val info: Boolean = false,
    /** A line of its own under the state. */
    val extra: String? = null,
    /** One app of the merged Battery row (BatteryMerge). */
    val battery: BatteryMerge.App? = null,
    val open: (EinkActivity) -> Unit,
) {
    /** Runs the row's action: behind the Settings PIN unless [pinFree]. */
    fun run(a: EinkActivity) = if (pinFree) open(a) else Pin.fix(a) { open(a) }

    fun row(extra: String? = this.extra): Checklist.Row = Checklist.Row(
        id = id, label = label, done = done, stateLine = detail, short = short, pending = pending,
        optional = optional, info = info, pinFree = pinFree, verb = action, extra = extra,
    )
}

object Setup {
    private const val BATTERY_DETAIL = "android.settings.VIEW_ADVANCED_POWER_USAGE_DETAIL"

    /** UserManager restrictions in force for this user (DeviceChecks.BLOCKING names the ones that matter). */
    private fun userRestrictions(ctx: Context): Set<String> = try {
        val b = (ctx.getSystemService(Context.USER_SERVICE) as android.os.UserManager).userRestrictions
        b.keySet().filter { b.getBoolean(it) }.toSet()
    } catch (e: Exception) {
        emptySet()
    }

    /** Device admins other than us (a managing app). */
    private fun otherAdmins(ctx: Context): List<String> = try {
        val dpm = ctx.getSystemService(Context.DEVICE_POLICY_SERVICE) as android.app.admin.DevicePolicyManager
        dpm.activeAdmins.orEmpty().map { it.packageName }.filter { it != ctx.packageName }.distinct()
    } catch (e: Exception) {
        emptyList()
    }

    /** Setup's rows: dismissed tips left out (SetupTips). */
    fun checks(ctx: Context): List<Check> {
        val all = allChecks(ctx)
        val keep = SetupTips.visible(all.map { it.id }, Prefs(ctx).hiddenTips).toSet()
        val shown = all.filter { it.id in keep }
        // The sleep screen's one optional row (docs/design/lock-screen.md P3), in either mode.
        return (if (Mode.isAddon(ctx)) addonChecks(ctx, shown) else shown) + listOfNotNull(SleepSetup.check(ctx), ScreenModeSetup.check(ctx), SharpCovers.check(ctx))
    }

    /**
     * Add-on's checklist (docs/design/addon-mode.md §4.3, companion-checklist §3.7): the four
     * required rows, the recommended-settings and Tailscale status lines, then the optional
     * rows, each saying what you get with it or lose without it, never counted, walked or prompted.
     */
    private fun addonChecks(ctx: Context, full: List<Check>): List<Check> {
        val byId = full.associateBy { it.id }
        val out = mutableListOf<Check>()
        full.filter { it.advisory }.forEach { out += it }
        // A frozen app is a warning on the app it breaks, only while it is frozen.
        byId["disabled"]?.takeIf { !it.done }?.let { out += it }
        // KOReader came back with another signer: Orbit ignores it until the user trusts it.
        byId[KoreaderTrust.ROW_ID]?.let { out += it }
        AddonLogic.REQUIRED.forEach { id -> byId[id]?.let { out += it } }
        byId["recommended"]?.let { out += it.asInfo() }
        if (Net.installed(ctx, Net.TAILSCALE_PKG)) byId["tailscale"]?.let { out += it.asInfo() }
        val p = Prefs(ctx)
        val map = ClickerStore.map(ctx)
        val batteryApps = full.filter { it.battery != null && it.battery.name != "Tailscale" }
        AddonLogic.optionalIds(Mode.helpers(ctx), map.mapped, Pin.isSet(ctx), map.sendsKeys).forEach { id ->
            val o = AddonLogic.optional(id) ?: return@forEach
            val granted = when (id) {
                "keyboard" -> KeySender.enabled(ctx)
                "battery" -> batteryApps.all { it.done }
                "wifi_switching" -> p.helperWifi
                "sleep_sync" -> p.helperSleepSync
                else -> AddonSetup.optionalGranted(ctx, id)
            }
            val fix: ((EinkActivity) -> Unit)? = when (id) {
                "battery" -> batteryApps.firstOrNull { !it.done }?.open
                "wifi_switching", "sleep_sync" -> { a -> a.startActivity(SettingsPage.section(a, "sync")) }
                else -> byId[id]?.open
            }
            val verb = if (id == "wifi_switching" || id == "sleep_sync") "Turn on" else "Allow"
            out += Check(o.title, granted, if (granted) "On: ${o.on}" else "", action = if (granted) null else verb, optional = true, id = id,
                battery = null) { a ->
                p.addonAsked = p.addonAsked + id
                OLog.i("setup: add-on optional $id: $verb")
                fix?.invoke(a)
            }
        }
        byId[ReadingFonts.ID]?.let { out += it }
        return out
    }

    private fun Check.asInfo() = Check(label, done, detail, pending, action, pinFree, advisory, optional, id, short, info = true, extra = extra, battery = battery, open = open)

    /** Dismissed tips that "Show hidden tips" would bring back. */
    fun hiddenTips(ctx: Context): Int = Prefs(ctx).hiddenTips.count { SetupTips.isTip(it) }

    /**
     * The checklist's rows (pure) from [checks]: tips left out, the battery apps merged into one
     * row, Key Mapper a line on the Clicker row, the frozen-app row only while something is frozen.
     */
    fun rows(checks: List<Check>): List<Checklist.Row> {
        val out = mutableListOf<Checklist.Row>()
        val battery = checks.filter { it.battery != null }
        val keymapper = checks.firstOrNull { it.id == "keymapper" }?.label
        checks.forEach { c ->
            when {
                c.advisory || c.id == "keymapper" -> Unit
                c.id == "disabled" && c.done -> Unit
                c.battery != null -> if (c === battery.first()) out += BatteryMerge.row(battery.map { it.battery!! })
                c.id == "clicker" -> out += c.row(extra = keymapper?.let { "$it · two key filters fight: turn it off once BookSync's buttons work" })
                else -> out += c.row()
            }
        }
        return out
    }

    fun items(ctx: Context, checks: List<Check> = checks(ctx)): List<Checklist.Item> {
        val p = Prefs(ctx)
        val from = NewIn.versionOf(p.updatedFromCode)
        val current = Version.parse(BuildConfig.VERSION_NAME)
        return Checklist.items(rows(checks), p.setupIgnored, p.setupLastDone) { r -> NewIn.tag(r.id, r.done, from, current) }
    }

    /** The status page's card and the launcher: the same summary as the Setup page. */
    fun summary(ctx: Context, items: List<Checklist.Item> = items(ctx)): Checklist.Summary =
        Checklist.summary(items, firstRun = Prefs(ctx).setupWelcome, locked = Pin.locked(ctx))

    /** The Check that runs an item's verb: for Battery, the first app not done. */
    fun checkFor(i: Checklist.Item, checks: List<Check>): Check? =
        if (i.id == "battery" && !i.row.optional) checks.firstOrNull { it.battery != null && it.id in i.row.ids }
        else checks.firstOrNull { it.id == i.id }

    /** The Details page's lines (§3.6): raw states, internals included, nothing counted. */
    fun details(ctx: Context): List<Pair<String, String>> {
        val p = Prefs(ctx)
        val out = mutableListOf<Pair<String, String>>()
        out += "BookSync plugin last answered" to if (p.patchSeenAt > 0) "${Ui.clock(ctx, p.patchSeenAt)} (${p.patchSeenVia})" else "never"
        out += "Plugin version KOReader runs" to p.patchVersionSeen.ifEmpty { "not reported" }
        out += "Plugin file version" to (PatchInstaller.installedVersion() ?: "unreadable")
        out += "KOReader" to "${Installers.koreaderVersion(ctx) ?: "-"} (${Installers.koreaderState(ctx)})"
        out += "library plugin" to (Installers.pluginVersion() ?: "not found")
        out += "Signed in (from the plugin)" to when (p.reportSignedIn) { "1" -> "yes"; "0" -> "no"; else -> "not reported" }
        out += "Recommended settings" to "${p.reportRecommended.ifEmpty { "not reported" }} · ${p.reportConflicts} conflicts"
        allChecks(ctx).mapNotNull { it.battery }.forEach { b -> out += "Battery: ${b.name}" to "${BatteryMerge.appLine(b)} (${b.row.detail})" }
        val ts = Net.appState(ctx, Net.TAILSCALE_PKG)
        out += "Tailscale" to listOf(
            when { ts == AppState.MISSING -> "not installed"; ts == AppState.FROZEN -> "frozen"; Net.tailscaleVpnUp(ctx) -> "connected"; else -> "not connected" },
            "Always-on: ${Net.alwaysOnVpnApp(ctx)?.ifEmpty { null } ?: "unknown"}",
            when (Net.vpnLockdown(ctx)) { true -> "lockdown on"; false -> "no lockdown"; null -> "lockdown unknown" },
        ).joinToString(" · ")
        out += "Frozen apps" to Vendor.disabledApps(ctx).joinToString().ifEmpty { "none" }
        val h = Mode.helpers(ctx)
        out += "Mode, helpers" to when (p.mode) {
            OrbitMode.ADDON -> "Add-on · " + listOfNotNull("Wi-Fi".takeIf { h.wifi }, "sleep sync".takeIf { h.sleepSync }, "screen off".takeIf { h.screenOff },
                "clicker".takeIf { h.clicker }, "PIN".takeIf { h.pin }).joinToString().ifEmpty { "no helpers" }
            OrbitMode.FULL -> "Full"
            null -> "not chosen"
        }
        out += "Wi-Fi off/on test" to if (p.wifiTestAt > 0) "${Ui.clock(ctx, p.wifiTestAt)} ${if (p.wifiTestOk) "passed" else "failed"}: ${p.wifiTestSummary}" else "never run"
        out += "Skipped steps" to p.setupIgnored.sorted().joinToString().ifEmpty { "none" }
        out += "Reader" to "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}, Android ${android.os.Build.VERSION.RELEASE}"
        return out
    }

    /**
     * Reading fonts (docs/design/reading-fonts.md): Optional in both modes, off until the user
     * turns it on. Turn on/off goes behind the Settings PIN; Restart KOReader is follow-through.
     */
    internal fun readingFonts(ctx: Context): Check {
        val p = Prefs(ctx)
        val wanted = p.fontsWanted
        val busy = FontInstaller.busy
        val installed = FontInstaller.installed()
        val restart = p.fontsRestartPending
        val done = wanted && installed
        val verb = ReadingFonts.verb(wanted, busy, installed, restart)
        return Check(
            ReadingFonts.LABEL, done, if (done) "On: ${Checklist.ON.getValue(ReadingFonts.ID)}" else "",
            action = verb, optional = true, id = "reading_fonts", short = "Reading fonts",
            pinFree = verb == "Restart KOReader",
            extra = ReadingFonts.extra(wanted, busy, installed, restart, p.fontsStatus),
        ) { a ->
            when (verb) {
                "Restart KOReader" -> FontInstaller.follow(a, "setup", manual = true)
                "Turn off" -> FontInstaller.set(a, false) { a.refresh() }
                null -> Unit
                else -> if (!PatchInstaller.hasPermission(a)) {
                    p.fontsWanted = true
                    a.requestPermissions(arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE), FontInstaller.REQUEST_CODE)
                } else FontInstaller.set(a, true) { a.refresh() }
            }
            OLog.i("setup: reading fonts: ${verb ?: "busy"}")
            a.refresh()
        }
    }

    private fun allChecks(ctx: Context): List<Check> {
        val prefs = Prefs(ctx)
        val list = mutableListOf<Check>()

        // Up front: what will get in the way, in plain words (DeviceChecks).
        val managed = DeviceChecks.managed(
            Net.installed(ctx, DeviceChecks.FAMILY_LINK),
            userRestrictions(ctx),
            otherAdmins(ctx),
        )
        if (managed != null) {
            list.add(Check(if (Net.installed(ctx, DeviceChecks.FAMILY_LINK)) "Family Link supervision" else "Managed device", false, managed, action = "Help", advisory = true, id = "managed") { a ->
                Ui.note(a, managed)
            })
        }
        if (Net.appState(ctx, DeviceChecks.PLAY_STORE) == AppState.OK) {
            list.add(Check("Play Protect scans installs", true, DeviceChecks.playProtect(), action = "Help", advisory = true, id = "play_protect") { a ->
                Ui.note(a, DeviceChecks.playProtect())
            })
        }

        // Some vendor launchers "freeze" (disable) apps behind our back (Vendor.kt). It is a
        // fault, not a step: a row only while an app is frozen, named after the app it breaks.
        val frozen = Vendor.disabledApps(ctx)
        val disabler = Vendor.disablerLabel(ctx)
        list.add(
            Check(
                frozen.joinToString().ifEmpty { "Apps" },
                frozen.isEmpty(),
                if (frozen.isEmpty()) "Not frozen"
                else "Frozen by ${disabler ?: "the system"}${Vendor.profile(ctx).freezeHint?.let { h -> ". Re-enable in ${disabler ?: "the launcher"} › $h" } ?: ""}",
                action = "Re-enable",
                id = "disabled",
            ) { a ->
                a.tryStart(Vendor.reenablePage(ctx), "re-enable page")
            },
        )
        val freezeHint = Vendor.profile(ctx).freezeHint
        if (frozen.isEmpty() && freezeHint != null) {
            val tip = "This ${disabler ?: "launcher"} can freeze apps it thinks are unused. If KOReader or BookSync stop working, Setup says so; to prevent it, set them to never freeze in $freezeHint."
            list.add(Check("Launcher can freeze apps", true, tip, action = "Help", advisory = true, id = "freeze_tip") { a ->
                a.tryStart(Vendor.reenablePage(ctx), "freeze settings")
            })
        }

        val canInstall = ctx.packageManager.canRequestPackageInstalls()
        list.add(Check("Install apps", canInstall, if (canInstall) "Allowed: KOReader and updates" else "Not allowed", action = "Allow", id = "install_updates") { a ->
            a.tryStart(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${ctx.packageName}")), "install unknown apps")
        })

        // Setup installs the rest: KOReader, the library plugin, the patch (Installers).
        val ko = Installers.koreaderState(ctx)
        val koV = Installers.koreaderVersion(ctx)
        val koOk = ko == KoreaderRelease.State.OFFICIAL
        list.add(
            Check(
                "KOReader",
                koOk,
                when {
                    Installers.busy(Installers.KOREADER) -> "Downloading…"
                    koOk -> "Version ${koV ?: "?"}${prefs.koreaderInstallStatus.takeIf { it.isNotEmpty() }?.let { " · $it" } ?: ""} · tap to check for an update"
                    prefs.koreaderInstallStatus.isNotEmpty() && ko == KoreaderRelease.State.MISSING -> "Not installed: ${prefs.koreaderInstallStatus}"
                    ko == KoreaderRelease.State.MISSING -> "Not installed"
                    else -> KoreaderRelease.explain(ko)
                },
                action = if (koOk) null else if (ko == KoreaderRelease.State.OTHER_SIGNER) "Open"
                    else if (KoreaderRelease.manualInstall(Mode.isAddon(ctx), canInstall, ko)) "Install it yourself" else "Install",
                id = "koreader",
                short = "KOReader${koV?.let { " $it" } ?: ""}",
            ) { a ->
                if (ko == KoreaderRelease.State.OTHER_SIGNER) {
                    a.tryStart(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${Koreader.PKG}")), "KOReader app info")
                } else if (KoreaderRelease.manualInstall(Mode.isAddon(a), a.packageManager.canRequestPackageInstalls(), ko)) {
                    a.tryStart(Intent(Intent.ACTION_VIEW, Uri.parse(KoreaderRelease.MANUAL_URL)), "KOReader download")
                } else if (!a.packageManager.canRequestPackageInstalls()) {
                    prefs.koreaderInstallStatus = "allow BookSync to install apps first (Install apps)"
                    a.tryStart(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${a.packageName}")), "install unknown apps")
                } else {
                    Installers.koreader(a) { a.refresh() }
                    a.refresh()
                }
            },
        )

        // The caller check (docs/design/security.md): KOReader came back with another signer.
        KoreaderTrust.changed(ctx)?.let { c ->
            list.add(Check("KOReader changed", false, "KOReader changed: trust this copy? BookSync ignores it until you do.",
                action = "Trust", id = KoreaderTrust.ROW_ID, short = "KOReader trusted") { a ->
                KoreaderTrust.trustChanged(a)
                OLog.i("setup: KOReader ${c.pkg} trusted")
                a.refresh()
            })
        }

        val plV = Installers.pluginVersion()
        val plNeeds = ServerAdapters.connector.needsInstall(plV)
        list.add(
            Check(
                "library plugin",
                !plNeeds,
                when {
                    Installers.busy(Installers.PLUGIN) -> "Downloading…"
                    !plNeeds -> "Version $plV · it updates itself from your library server"
                    prefs.pluginInstallStatus.isNotEmpty() -> "Not installed: ${prefs.pluginInstallStatus}"
                    plV == null -> "Not installed"
                    else -> "Older than the BookSync plugin needs (v${ServerAdapters.connector.minimumVersion})"
                },
                action = if (!plNeeds) null else if (plV == null) "Install" else "Update",
                id = "plugin",
                short = "library plugin",
            ) { a ->
                if (plNeeds && !Installers.busy(Installers.PLUGIN)) Installers.pluginFrom(a) { a.refresh() }
                a.refresh()
            },
        )

        // The file decides "outdated"; the version the running patch reports decides "restart".
        val fileV = PatchInstaller.installedVersion()
        val runningV = prefs.patchVersionSeen.takeIf { it.isNotEmpty() }
        val patchState = PatchRow.state(fileV, runningV, BuildConfig.VERSION_NAME)
        val patchV = fileV ?: runningV
        // D8: never answered yet: "Checking…" until KOReader has run it once.
        val neverSeen = patchState == PatchRowState.CURRENT && prefs.patchSeenAt <= 0L
        list.add(
            Check(
                "BookSync plugin",
                patchState == PatchRowState.CURRENT || patchState == PatchRowState.RESTART,
                when {
                    PatchInstaller.busy -> "Installing…"
                    patchState == PatchRowState.RESTART && PatchRow.canRestart(runningV) ->
                        "Installed; KOReader still runs $runningV. It restarts when the screen next goes off."
                    patchState == PatchRowState.RESTART -> "Installed; KOReader still runs $runningV. Close KOReader from recent apps and open it again."
                    patchState == PatchRowState.MISSING && prefs.patchInstallStatus.isNotEmpty() -> "Not installed: ${prefs.patchInstallStatus}"
                    patchState == PatchRowState.MISSING -> "Not installed"
                    patchState == PatchRowState.OUTDATED -> "Older than this app (${BuildConfig.VERSION_NAME})"
                    neverSeen -> "Checking… open KOReader once"
                    else -> "Version $patchV"
                },
                pending = patchState == PatchRowState.RESTART || neverSeen,
                action = when {
                    PatchInstaller.busy -> null
                    patchState == PatchRowState.MISSING -> "Install"
                    patchState == PatchRowState.OUTDATED -> "Update"
                    patchState == PatchRowState.RESTART && PatchRow.canRestart(runningV) -> "Restart KOReader"
                    else -> null
                },
                // Update follow-through (this release's patch, a restart): changes no setting, no PIN.
                pinFree = true,
                id = "patch",
                short = "BookSync plugin${patchV?.let { " $it" } ?: ""}",
            ) { a ->
                when {
                    PatchInstaller.busy -> Unit
                    patchState == PatchRowState.RESTART -> if (PatchRow.canRestart(runningV)) Koreader.restart(a, "setup: new patch installed")
                    neverSeen -> Koreader.start(a, "setup: patch check", null)
                    else -> PatchInstaller.installFrom(a) { a.refresh() }
                }
                a.refresh()
            },
        )

        list.add(Check("Sign in to your server", LibraryAccount.state()["signedIn"] == true,
            if (LibraryAccount.state()["signedIn"] == true) "Signed in" else "Account-wide reading statistics",
            action = "Open", id = "server_account", short = "Server account", optional = true) { a ->
            a.startActivity(Intent(a, AccountActivity::class.java))
        })
        // From the Orbit plugin's REPORT (docs/design/addon-mode.md §4.2, §7.3).
        // Pending ("Checking…") while the running plugin is older than REPORT or none came yet.
        LibraryAccount.initialize(ctx)
        val signed = PluginReport.signedInRow(prefs.reportSignedIn, runningV)
        list.add(Check("library account", signed.done && !signed.pending,
            when { signed.pending -> "Checking… open KOReader once"; signed.done -> "Signed in"; else -> "Not signed in" },
            pending = signed.pending, action = if (signed.pending) null else "Sign in", id = "signed_in", short = "Signed in", optional = true) { a ->
            Koreader.start(a, "setup: sign in to library", HomeCommands.SIGNIN)
        })
        val rec = PluginReport.recommendedRow(prefs.reportRecommended, prefs.reportConflicts, runningV)
        list.add(Check("Recommended settings", rec.done && !rec.pending,
            when {
                rec.pending && prefs.reportRecommended == "none" -> "Applied at KOReader's next start"
                rec.pending -> "Checking… open KOReader once"
                prefs.reportRecommended == "reviewed" -> "Reviewed"
                rec.done -> "Applied"
                else -> "${prefs.reportConflicts} of yours differ"
            },
            pending = rec.pending, action = if (rec.pending) null else "Review", pinFree = false, id = "recommended",
            short = if (prefs.reportRecommended == "reviewed") "recommended settings reviewed" else "recommended settings on") { a ->
            Koreader.start(a, "setup: recommended settings", HomeCommands.RECOMMENDED)
        })

        val home = ctx.packageManager.resolveActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), android.content.pm.PackageManager.MATCH_DEFAULT_ONLY,
        )?.activityInfo?.packageName
        val isHome = home == ctx.packageName
        list.add(Check("Home app", isHome, if (isHome) "BookSync is the Home app" else "Now: ${home?.let { HomeTarget.label(ctx, it) } ?: "ask every time"}",
            action = "Set", id = "home") { a ->
            a.tryStart(Intent(Settings.ACTION_HOME_SETTINGS), "Home app settings") ||
                a.tryStart(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS), "default apps settings")
        })

        val notif = Net.notificationsEnabled(ctx)
        list.add(Check("Notifications", notif, if (notif) "Allowed" else "Off", action = "Allow", id = "notifications") { a ->
            a.tryStart(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, ctx.packageName),
                "notification settings",
            )
        })

        // Battery: one row per installed app, merged on the page (BatteryMerge); the ids stay per app.
        listOf(ctx.packageName to "BookSync", Koreader.PKG to "KOReader", Net.TAILSCALE_PKG to "Tailscale").forEach { (pkg, name) ->
            if (pkg != ctx.packageName && !Net.installed(ctx, pkg)) return@forEach
            val row = Net.batteryRow(ctx, pkg)
            val app = BatteryMerge.App(name, row, locked = pkg == ctx.packageName && Net.adminActive(ctx))
            list.add(Check("Battery: $name", row.done, BatteryMerge.appLine(app), action = BatteryMerge.appVerb(app), id = "battery:$name", battery = app) { a ->
                // Android's "Allow" prompt works even where Settings shows "not available" (BatteryRow).
                (row.open == BatteryRow.Open.PROMPT &&
                    a.tryStart(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$pkg")), "battery prompt for $pkg")) ||
                    a.tryStart(Intent(BATTERY_DETAIL, Uri.parse("package:$pkg")), "battery page for $pkg") ||
                    a.tryStart(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg")), "app info for $pkg")
            })
        }

        val tsState = Net.appState(ctx, Net.TAILSCALE_PKG)
        // Done when a VPN is up and it is Tailscale's (owner UID, where Android lets us read it).
        // Always-on is advice only (Details): some firmwares hide "always_on_vpn_app" from apps.
        val tsUp = Net.tailscaleVpnUp(ctx)
        // Tailscale routes only the tailnet: lockdown blocks everything else (updates included).
        val lockdown = Net.vpnLockdown(ctx) == true
        list.add(
            Check(
                "Tailscale",
                tsUp && !lockdown,
                when {
                    tsState == AppState.MISSING -> "Not installed: get it from the Play Store"
                    tsState == AppState.FROZEN -> Vendor.disabledMessage(ctx, "Tailscale")
                    !tsUp -> "Not connected: open Tailscale and sign in"
                    lockdown -> NetErrors.LOCKDOWN_WARNING
                    else -> "Connected"
                },
                action = when {
                    tsState == AppState.MISSING -> null
                    tsState == AppState.FROZEN -> "Re-enable"
                    lockdown -> "Fix"
                    else -> "Connect"
                },
                id = "tailscale",
                short = "Tailscale connected",
            ) { a ->
                when {
                    tsState == AppState.FROZEN -> a.tryStart(Vendor.reenablePage(ctx, Net.TAILSCALE_PKG), "re-enable page")
                    lockdown || tsUp -> a.tryStart(Intent(Settings.ACTION_VPN_SETTINGS), "VPN settings")
                    else -> ctx.packageManager.getLaunchIntentForPackage(Net.TAILSCALE_PKG)?.let { a.tryStart(it, "Tailscale") }
                }
            },
        )

        val admin = Net.adminActive(ctx)
        list.add(Check("Screen lock", admin, if (admin) "Allowed: Sync and sleep turns the screen off" else "Not allowed", action = "Allow", id = "admin") { a ->
            a.tryStart(
                Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                    .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, AdminReceiver.component(ctx))
                    .putExtra(
                        DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                        "Lets \"Sync and sleep\" turn the screen off after syncing. It uses only the lock-screen permission.",
                    ),
                "device admin",
            )
        })

        // Clicker buttons: shown only once a clicker is mapped (android/docs/BTKEYS-DESIGN.md "Staying on").
        // With a Settings PIN set the app guard needs the same service, so the row shows then too.
        val pinSet = Pin.isSet(ctx)
        val clicker = ClickerRow.state(ClickerStore.map(ctx).mapped || pinSet, ClickerStore.enabled(ctx), ClickerService.connected)
        if (clicker != ClickerRowState.HIDDEN) {
            list.add(Check(
                if (pinSet) "Clicker buttons and app guard" else "Clicker buttons",
                clicker == ClickerRowState.DONE,
                when (clicker) {
                    ClickerRowState.DONE -> "On in every app"
                    ClickerRowState.OFF -> "Off. BookSync uses it only to see button presses and which app is in front, and to send page taps, Home and Back. It can't read what's on screen."
                    else -> "On in Android but not running yet: turn it off and on in Settings › Accessibility"
                },
                action = "Turn on",
                id = "clicker",
            ) { a -> a.tryStart(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS), "accessibility settings") })
            val others = ClickerRow.others(ClickerStore.accessibilitySetting(ctx), ctx.packageName)
            others.firstOrNull()?.let { other ->
                val km = other == "io.github.sds100.keymapper"
                list.add(Check(
                    if (km) "Key Mapper is also on" else "${HomeTarget.label(ctx, other)} is also on",
                    false,
                    "Turn it off once BookSync's buttons work; you can then uninstall it. Two key filters both see every key and can fight.",
                    action = "Turn off",
                    id = "keymapper",
                ) { a -> a.tryStart(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS), "accessibility settings") })
            }
        }

        // Orbit keyboard: shown only while a Send-key action is mapped (android/docs/BTKEYS-DESIGN.md "Send key").
        if (ClickerStore.map(ctx).sendsKeys) {
            val on = KeySender.enabled(ctx)
            list.add(Check(
                "BookSync keyboard",
                on,
                if (on) "On: switches in only for a key press, then your keyboard comes back"
                else "Off. Turn on \"BookSync clicker keys\". It has no keys, never stays your keyboard and never reads what you type; Android's warning is the same for every keyboard.",
                action = "Turn on",
                id = "keyboard",
            ) { a -> a.tryStart(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS), "keyboard settings") })
        }

        list.add(readingFonts(ctx))

        list.add(
            Check(
                "Wi-Fi off/on test",
                prefs.wifiTestOk,
                when {
                    prefs.wifiTestAt <= 0 -> "Not run yet"
                    prefs.wifiTestOk -> "Passed ${Ui.clock(ctx, prefs.wifiTestAt)}: ${prefs.wifiTestSummary}"
                    else -> "Failed ${Ui.clock(ctx, prefs.wifiTestAt)}: ${prefs.wifiTestSummary}"
                },
                action = "Run",
                id = "wifi_test",
                short = if (prefs.wifiTestOk) "Wi-Fi test passed ${Ui.clock(ctx, prefs.wifiTestAt)}" else "Wi-Fi test",
                info = true,
            ) { a -> (a as? SetupActivity)?.runWifiTest() },
        )
        return list
    }
}

/** The Setup page (docs/design/companion-checklist.md). Rows re-check on resume. */
class SetupActivity : EinkActivity(), ChecklistUi.Actions {
    private var test: NetTest? = null

    /** "Fix next": walking the open rows in order, each once (SetupWalk). */
    private var walking = false
    private val tried = LinkedHashSet<String>()
    private var lastStep = 0L
    private var walkTotal = 0
    private var walkLabel = ""

    private var choiceShown = false

    /** The one open group (D2): a Group's name, "tips", or null. */
    private var openGroup: String? = null

    private var checks: List<Check> = emptyList()
    private var model: Checklist.Page? = null

    override fun onResume() {
        super.onResume()
        Mode.migrate(this, "setup page")
        if (!choiceShown && Prefs(this).mode == null) {
            choiceShown = true
            startActivity(Intent(this, ModeActivity::class.java))
        }
        render()
        if (walking) continueWalk("back in Setup")
    }

    private fun installing() = PatchInstaller.busy || Installers.busy(Installers.PLUGIN) || Installers.busy(Installers.KOREADER)

    /** The ids Fix next walks, in Needs-you order: counted rows only, skipped ones left out. */
    private fun walkable(): List<Pair<String, Boolean>> {
        val all = Setup.checks(this).filter { !it.optional && !it.advisory && !it.info }
        val addon = Mode.isAddon(this)
        val ignored = Prefs(this).setupIgnored
        val order = { id: String -> Checklist.NEED_ORDER.indexOf(id.substringBefore(':')).let { if (it < 0) Checklist.NEED_ORDER.size else it } }
        return all.filter { (!addon || it.id in AddonLogic.REQUIRED) && it.id !in ignored && !it.pending }
            .sortedBy { order(it.id) }
            .map { it.id to it.done }
    }

    private fun startWalk() {
        walking = true
        tried.clear()
        lastStep = 0
        walkTotal = walkable().count { !it.second && it.first !in SetupAttention.INFO_ONLY }
        Prefs(this).setupWelcome = false
        OLog.i("setup: Fix next started ($walkTotal steps)")
        continueWalk("start")
    }

    private fun stopWalk() {
        walking = false
        OLog.i("setup: Fix next stopped")
        render()
    }

    /** The next open row, once the last step is back (a page closed, an install finished). */
    private fun continueWalk(why: String) {
        if (!walking || isFinishing || installing()) return
        val now = android.os.SystemClock.elapsedRealtime()
        if (now - lastStep < 1_000) return
        val rows = walkable()
        val id = SetupWalk.next(rows, tried)
        val c = Setup.checks(this).firstOrNull { it.id == id }
        if (id == null || c == null) {
            walking = false
            OLog.i("setup: Fix next done ($why); ${rows.count { !it.second }} row(s) still open")
            render()
            return
        }
        tried.add(id)
        walkLabel = c.label
        walkTotal = maxOf(walkTotal, tried.size)
        lastStep = now
        OLog.i("setup: Fix next -> $id ($why)")
        render()
        c.run(this)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        val t = test
        if (!hasFocus && t != null && t.running) {
            t.focusLost = true
            OLog.i("Wi-Fi test: window lost focus (a system prompt?)")
        }
    }

    override fun onDestroy() {
        test?.cancel()
        super.onDestroy()
    }

    override fun refresh() {
        if (isFinishing) return
        render()
        // An in-app step (an install) finished: on to the next one.
        if (walking && hasWindowFocus()) main.postDelayed({ continueWalk("step finished") }, 1_200)
    }

    private val main = android.os.Handler(android.os.Looper.getMainLooper())

    fun runWifiTest() {
        if (test?.running == true) return
        test = NetTest(this, offFirst = true) { ok, summary ->
            val prefs = Prefs(this)
            prefs.wifiTestAt = System.currentTimeMillis()
            prefs.wifiTestOk = ok
            prefs.wifiTestSummary = summary
            render()
        }.also { it.start() }
        render()
    }

    private fun render() {
        val p = Prefs(this)
        checks = Setup.checks(this)
        val items = Setup.items(this, checks).map { i ->
            // The test row says it is running; no spinner, one redraw when it ends.
            if (i.id == "wifi_test" && test?.running == true) i.copy(row = i.row.copy(stateLine = "Running…", verb = null)) else i
        }
        val locked = Pin.locked(this)
        if (Checklist.count(items) == 0 && p.setupWelcome) p.setupWelcome = false
        val walk = if (walking && tried.isNotEmpty()) Triple(tried.size, walkTotal, walkLabel) else null
        val model = Checklist.page(items, firstRun = p.setupWelcome && !walking, walk = walk, locked = locked)
        this.model = model
        val root = page(scroll = true)
        root.addView(Ui.header(this, "Setup", "‹ Back") { finish() })
        val tips = checks.filter { it.advisory }
        val modeName = when (p.mode) { OrbitMode.ADDON -> "Add-on mode"; OrbitMode.FULL -> "Full mode"; null -> "No mode chosen yet" }
        val frame = ChecklistUi.Frame(
            tips = tips.filter { it.id != "managed" }.map { ChecklistUi.Tip(it.id, it.label, it.detail) },
            managed = tips.firstOrNull { it.id == "managed" }?.detail,
            hiddenTips = Setup.hiddenTips(this),
            detailsLine = if (p.patchSeenAt > 0) "Last heard from KOReader ${Ui.clock(this, p.patchSeenAt)}" else "KOReader hasn't reported yet",
            modeLine = "$modeName · change in Settings",
            open = openGroup,
        )
        ChecklistUi.render(this, root, model, frame, this)
    }

    // ChecklistUi.Actions

    override fun verb(i: Checklist.Item) {
        if (i.skipped || (i.state == Checklist.State.OFF && !i.row.optional && i.id != "wifi_test")) {
            // Allow on a skipped step: ask about it again, then fix it.
            val p = Prefs(this)
            p.setupIgnored = p.setupIgnored - i.row.ids.toSet()
            OLog.i("setup: asking about ${i.row.ids} again")
        }
        if (i.id == "battery" && i.row.verb == "Help") {
            startActivity(Intent(this, SetupBatteryActivity::class.java))
            return
        }
        val c = Setup.checkFor(i, checks) ?: return
        c.run(this)
        render()
    }

    override fun tap(i: Checklist.Item) {
        if (i.id == "battery" && !i.row.optional) {
            startActivity(Intent(this, SetupBatteryActivity::class.java))
            return
        }
        if (i.row.optional && i.row.done) return
        if (i.id == "wifi_test" && test?.running == true) return
        Setup.checkFor(i, checks)?.run(this)
        render()
    }

    override fun summaryButton() {
        when (val s = model?.summary) {
            is Checklist.Summary.Walking -> stopWalk()
            is Checklist.Summary.NeedsGrownUp -> Pin.run(this) { render() }
            is Checklist.Summary.NeedsYou, is Checklist.Summary.FirstRun -> startWalk()
            else -> OLog.i("setup: summary tapped ($s)")
        }
    }

    override fun group(key: String) {
        openGroup = Checklist.toggle(openGroup, key)
        render()
    }

    override fun gotIt(tipId: String) {
        val p = Prefs(this)
        p.hiddenTips = SetupTips.hide(p.hiddenTips, tipId)
        OLog.i("setup: tip $tipId hidden")
        render()
    }

    override fun showHiddenTips() {
        Prefs(this).hiddenTips = emptySet()
        OLog.i("setup: hidden tips shown again")
        render()
    }

    override fun details() = SetupDetailsActivity.open(this)

    override fun mode() {
        startActivity(Intent(this, ModeActivity::class.java))
    }
}

/**
 * Settings › Home opens: KOReader + library (default), then reader apps (KnownApps and the
 * vendor's), then every other launchable app A–Z. Paged, no scrolling.
 */
class HomeAppActivity : EinkActivity() {
    override val pinGuarded = true

    private var apps: List<Pair<String, String>> = emptyList()
    private var readers: Set<String> = emptySet()
    private var pageIndex = 0

    override fun onResume() {
        super.onResume()
        val found = AppList.load(this).map { it.pkg to it.label }
        readers = KnownApps.readers(Vendor.profile(this))
        apps = HomeApp.order(found, readers)
        render()
    }

    private fun render() {
        val root = page()
        root.addView(Ui.header(this, "Home opens", "‹ Back") { finish() })
        val current = Prefs(this).homeApp
        val rows = listOf(HomeApp.KOREADER_LIBRARY to "KOReader + library", HomeApp.LAUNCHER to HomeApp.LAUNCHER_LABEL) + apps
        val perPage = maxOf(3, (resources.displayMetrics.heightPixels / resources.displayMetrics.density).toInt().minus(300) / (Ui.ROW_DP + 4))
        val pages = maxOf(1, (rows.size + perPage - 1) / perPage)
        pageIndex = pageIndex.coerceIn(0, pages - 1)
        rows.drop(pageIndex * perPage).take(perPage).forEach { (pkg, label) ->
            val sub = when {
                pkg == HomeApp.KOREADER_LIBRARY -> "Smart Home, sync on sleep, Just in time Wi-Fi"
                pkg == HomeApp.LAUNCHER -> "BookSync's own page of apps"
                pkg in readers -> "reader app"
                else -> null
            }
            val chosen = if (HomeApp.isKoreader(current)) pkg == HomeApp.KOREADER_LIBRARY else pkg == current
            root.addView(Ui.row(this, label, sub, Ui.check(this, chosen), onClick = {
                Prefs(this).homeApp = pkg
                OLog.i("settings: Home opens ${if (pkg.isEmpty()) "KOReader + library" else pkg}")
                finish()
            }))
        }
        root.addView(android.view.View(this), android.widget.LinearLayout.LayoutParams(1, 0, 1f))
        root.addView(Ui.text(this, "Another app: Home brings it back where it was; press Home twice for the launcher page. Sync on sleep, Just in time Wi-Fi and library home work only inside KOReader.", 15f, color = Ui.MID))
        if (pages > 1) {
            root.addView(Ui.gap(this, 8))
            root.addView(Ui.weightRow(this,
                Ui.button(this, "‹ Back", heightDp = 64, sp = 18f) { if (pageIndex > 0) { pageIndex--; render() } },
                Ui.text(this, "${pageIndex + 1} / $pages", 17f, color = Ui.MID).apply { gravity = android.view.Gravity.CENTER },
                Ui.button(this, "Next ›", heightDp = 64, sp = 18f) { if (pageIndex < pages - 1) { pageIndex++; render() } }))
        }
    }
}
