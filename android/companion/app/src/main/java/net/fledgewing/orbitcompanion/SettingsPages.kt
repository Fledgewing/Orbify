package net.fledgewing.orbitcompanion

import android.app.AlertDialog
import android.content.Intent
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.InputFilter
import android.text.InputType
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.LinearLayout
import java.io.File

/**
 * The Settings pages (docs/design/companion-settings.md §5): a top page with search and eight
 * sections, one page per section drawn from the shared schema plus the companion's own rows.
 * Behind the Settings PIN they open read-only: values and lines, no controls, one Unlock button
 * (§4.7). A change shows "Waiting for KOReader" until the plugin reports it back (§4.5).
 */
abstract class SettingsPage : EinkActivity() {
    // Read-only while locked (no keypad on open); staying on these pages keeps an unlock.
    override val pinPage: PinPage get() = PinPage.PROTECTED

    protected val schema: SettingsSchema get() = SettingsStore.schema(this)
    protected val prefs: Prefs by lazy { Prefs(this) }
    protected val locked: Boolean get() = forceLocked ?: Pin.locked(this)

    override fun onResume() {
        super.onResume()
        render()
    }

    abstract fun render()

    override fun refresh() = render()

    /** Locked: one line and Unlock; the page redraws with its controls once the PIN is right. */
    protected fun lockedBar(root: LinearLayout) {
        if (!locked) return
        root.addView(Ui.card(this).apply {
            addView(Ui.text(this@SettingsPage, "Settings are locked. You can look; changes need the PIN.", CompanionStyle.BODY))
            addView(Ui.gap(this@SettingsPage, 8))
            addView(Ui.button(this@SettingsPage, "Unlock", heightDp = 56, sp = 20f) { Pin.run(this@SettingsPage) { render() } })
        })
        root.addView(Ui.gap(this, 12))
    }

    protected fun note(text: String) = Ui.text(this, text, 16f, color = Ui.MID).apply {
        setPadding(0, Ui.dp(this@SettingsPage, 6), 0, Ui.dp(this@SettingsPage, 8))
    }

    protected fun subhead(root: LinearLayout, title: String) {
        root.addView(Ui.text(this, title.uppercase(), CompanionStyle.CAPTION, bold = true).apply { setPadding(0, Ui.dp(this@SettingsPage, 14), 0, Ui.dp(this@SettingsPage, 6)) })
    }

    /** A changed shared key: stored with its time, told to the plugin, the page redrawn once. */
    protected fun setShared(key: String, wire: String) {
        if (locked) return
        SettingsStore.set(this, key, wire, "settings page")
        OLog.debug = prefs.debugLog
        render()
    }

    /**
     * The row's line: what it does; then, on a line of its own, Waiting for KOReader or Changed in
     * KOReader at … (M8C feedback: never squeezed in beside the text).
     */
    protected fun lineFor(d: SettingDef): String = SettingsUi.line(d, statusFor(d))

    private fun statusFor(d: SettingDef): String? = when {
        SettingsStore.pending(this, d.key) -> SettingsUi.WAITING
        else -> SettingsStore.fromPluginAt(this, d.key)?.takeIf { System.currentTimeMillis() - it < 86_400_000L }?.let {
            "Changed in KOReader at ${Ui.clock(this, it)}"
        }
    }

    /** [title]: null when the page's own title already names it (no doubled titles). */
    protected fun <T> segmented(root: LinearLayout, title: String?, sub: String?, options: List<Pair<T, String>>, current: T, pick: (T) -> Unit) {
        if (title != null) root.addView(Ui.text(this, title, CompanionStyle.LABEL, bold = true).apply { setPadding(0, Ui.dp(this@SettingsPage, 10), 0, Ui.dp(this@SettingsPage, 6)) })
        val rows = if (options.size == 4) options.chunked(2) else listOf(options)
        rows.forEach { row ->
            val seg = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                // Equal-width labels may wrap differently; baseline alignment can
                // shift a multiline label below the row's clipping outline.
                isBaselineAligned = false
                background = Ui.box(this@SettingsPage, Ui.PAPER)
                clipToOutline = true
                val pad = Ui.dp(this@SettingsPage, 2)
                setPadding(pad, pad, pad, pad)
            }
            row.forEach { (value, label) ->
                val sel = value == current
                val t = Ui.text(this, label, CompanionStyle.CONTROL, bold = sel, color = if (sel) Ui.PAPER else Ui.INK).apply {
                    gravity = Gravity.CENTER
                    minHeight = Ui.dp(this@SettingsPage, 64)
                    setBackgroundColor(if (sel) Ui.INK else Ui.PAPER)
                }
                if (!locked) Ui.clickable(t, { if (!sel) pick(value) })
                seg.addView(t, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            }
            root.addView(seg)
        }
        if (!sub.isNullOrEmpty()) root.addView(note(sub))
    }

    protected fun toggleRow(root: LinearLayout, label: String, sub: String?, on: Boolean, set: (Boolean) -> Unit): View =
        Ui.row(this, label, sub, Ui.toggle(this, on), onClick = if (locked) null else ({ set(!on) })).also { root.addView(it) }

    protected fun linkRow(root: LinearLayout, label: String, sub: String?, value: String = "›", open: () -> Unit): View =
        Ui.row(this, label, sub, Ui.value(this, value), onClick = open).also { root.addView(it) }

    companion object {
        /** Tests: draw as if the PIN were locked (true) or unlocked (false); null = the real lock. */
        @Volatile
        internal var forceLocked: Boolean? = null

        const val EXTRA_SECTION = "section"
        const val EXTRA_FOCUS = "focus"
        const val EXTRA_KEY = "key"

        /** The Updates section's App version row (Check for updates, Install, "Updated to v…"). */
        const val UPDATE_ROW = "app_version"

        fun section(ctx: android.content.Context, id: String, focus: String? = null): Intent =
            Intent(ctx, if (id == "sleep") SleepScreenActivity::class.java else SettingsSectionActivity::class.java)
                .putExtra(EXTRA_SECTION, id).apply { focus?.let { putExtra(EXTRA_FOCUS, it) } }

        /**
         * What the top page opens for a section: the section page, or, when that page would hold
         * one row that only opens another page, that page itself (no in-between screens).
         */
        fun open(ctx: android.content.Context, id: String): Intent {
            val p = Prefs(ctx)
            return when (SettingsUi.direct(id, p.mode == OrbitMode.ADDON, Pin.isSet(ctx))) {
                SettingsUi.Direct.CLICKERS -> Intent(ctx, ClickersActivity::class.java)
                SettingsUi.Direct.PIN_SET -> PinActivity.intent(ctx, PinActivity.Mode.SET)
                null -> section(ctx, id)
            }
        }
    }
}

/** Settings: search, then the eight sections with their state in one line (§5.1). */
class SettingsActivity : SleepPickerPage() {
    private val main = Handler(Looper.getMainLooper())
    private var query = ""
    private var results: LinearLayout? = null
    private val searchNow = Runnable { drawResults() }

    override fun onPause() {
        super.onPause()
        main.removeCallbacks(searchNow)
    }

    override fun render() {
        val root = page(scroll = true)
        root.addView(Ui.header(this, "Settings", "‹ Back") { finish() })
        lockedBar(root)
        // The search box: the input, and ✕ at its right end to clear it in one tap.
        val clear = Ui.text(this, "✕", 22f, bold = true).apply {
            gravity = Gravity.CENTER
            minWidth = Ui.dp(this@SettingsActivity, 56)
            minHeight = Ui.dp(this@SettingsActivity, 56)
            contentDescription = "Clear search"
            tag = "search:clear"
            visibility = if (query.isEmpty()) View.GONE else View.VISIBLE
        }
        val box = Ui.input(this).apply {
            hint = "Search settings"
            setText(query)
            setSingleLine()
            textSize = CompanionStyle.textSize(this@SettingsActivity, CompanionStyle.BODY)
            imeOptions = EditorInfo.IME_ACTION_SEARCH
            minHeight = Ui.dp(this@SettingsActivity, 64)
            background = null
            val p = Ui.dp(this@SettingsActivity, 12)
            setPadding(p, 0, 0, 0)
            tag = "search"
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
                override fun afterTextChanged(s: Editable?) {
                    query = s?.toString().orEmpty()
                    clear.visibility = if (query.isEmpty()) View.GONE else View.VISIBLE
                    // One redraw per pause in typing, none per key (§5.4).
                    main.removeCallbacks(searchNow)
                    main.postDelayed(searchNow, SEARCH_PAUSE_MS)
                }
            })
        }
        Ui.clickable(clear, {
            box.setText("")
            // Cleared: the sections at once, no pause.
            main.removeCallbacks(searchNow)
            drawResults()
        })
        root.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = Ui.box(this@SettingsActivity, Ui.PAPER)
            addView(box, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(clear, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        })
        root.addView(Ui.gap(this, 8))
        results = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.addView(results)
        drawResults()
    }

    /** The section list, or search results in its place. */
    internal fun drawResults() {
        val out = results ?: return
        out.removeAllViews()
        val q = query.trim()
        if (q.isEmpty()) {
            schema.sections.forEach { s ->
                out.addView(Ui.row(this, s.title, summary(s.id), Ui.value(this, "›"), onClick = { startActivity(SettingsPage.open(this, s.id)) }, left = CompanionStyle.icon(this, s.id)).apply { tag = "section:${s.id}" })
            }
            out.addView(Ui.gap(this, 8))
            out.addView(Ui.weightRow(this,
                Ui.row(this, "Your server", onClick = {
                    startActivity(Intent(this, AccountActivity::class.java))
                }, left = CompanionStyle.icon(this, "server")).apply { tag = "server" },
                Ui.row(this, "About", onClick = {
                    startActivity(Intent(this, AboutActivity::class.java))
                }, left = CompanionStyle.icon(this, "about")).apply { tag = "about" },
            ))
            out.addView(note("BookSync ${BuildConfig.VERSION_NAME}" + prefs.patchVersionSeen.takeIf { it.isNotEmpty() }?.let { " · plugin $it" }.orEmpty()))
            return
        }
        val hits = SettingsUi.search(schema, q)
        if (hits.isEmpty()) {
            out.addView(note("Nothing matches \"$q\". Try Wi-Fi, sleep, PIN or storage."))
            return
        }
        var last: String? = null
        val get = { k: String -> SettingsStore.get(this, k) }
        hits.forEach { h ->
            if (h.section != last) {
                last = h.section
                out.addView(Ui.text(this, schema.section(h.section)?.title.orEmpty(), 16f, bold = true, color = Ui.MID).apply { setPadding(0, Ui.dp(this@SettingsActivity, 10), 0, 0) })
            }
            val d = schema.byKey[h.id]
            val shown = d == null || SettingsSync.visible(schema, h.id, get)
            val sub = when {
                d == null -> null
                !shown -> SettingsUi.shownWhen(schema, h.id)
                else -> SettingsUi.valueLabel(d, get(h.id))
            }
            // A hidden row opens its section at the parent that shows it.
            val focus = if (shown) h.id else d?.parentKey
            // A section that is one row leading on (Buttons, a PIN not set yet) opens where that row goes.
            val go = { startActivity(if (h.section in DIRECT_IDS) SettingsPage.open(this, h.section) else SettingsPage.section(this, h.section, focus)) }
            out.addView(Ui.row(this, h.label, sub, Ui.value(this, "›"), onClick = go).apply { tag = "hit:${h.id}" })
        }
    }

    /** Each section's state in one line (§5.1). */
    private fun summary(id: String): String {
        val g = { k: String -> SettingsStore.get(this, k) }
        fun label(k: String) = schema.byKey[k]?.let { SettingsUi.valueLabel(it, g(k), choices) }.orEmpty()
        val line = when (id) {
            "reading" -> "Home: ${label("home_button")} · end-of-book sheet ${if (g("eob_sheet") == "1") "on" else "off"}"
            "sleep" -> if (g("sleep_mode") == "off") "The reader's own" else "${label("sleep_mode")}" +
                if (g("sleep_mode") == "recommended") " · ${label("sleep_from")} · every ${g("sleep_hours")} h" else ""
            "sync" -> listOfNotNull(
                label("wifi_mode").takeIf { "wifi" in Mode.caps(this) },
                // OrbiSmart sets the sync rows itself (docs/design/position-sync.md §6).
                if (g("sync_mode") != "custom") "Reading position: Furthest page wins"
                else listOfNotNull("sleep".takeIf { g("sync_on_sleep") == "1" }, "wake".takeIf { g("sync_on_wake") == "1" }).let { if (it.isEmpty()) "no automatic syncs" else "sync on " + it.joinToString(" and ") },
            ).joinToString(" · ")
            "library" -> "Limit ${label("storage_limit_mb")} · " + if (g("mirror_auto") == "1") "Full refresh every ${label("mirror_ttl_days")}" else "Full refresh by hand"
            "buttons" -> "Bluetooth page clicker buttons"
            "kids" -> if (Pin.isSet(this)) "PIN on · ${Pin.guarded(this).size} guarded apps" else "PIN off"
            "setup" -> when (prefs.mode) { OrbitMode.ADDON -> "Add-on mode"; OrbitMode.FULL -> "Full mode"; null -> "Mode not chosen yet" }
            "updates" -> Updater.statusLine(this) + if (g("auto_update_patch") == "1") " · automatic" else ""
            else -> ""
        }
        val waiting = schema.settings.count { it.section == id && !it.hidden && SettingsStore.pending(this, it.key) }
        return if (waiting > 0) "$line · … $waiting waiting for KOReader" else line
    }

    companion object {
        const val SEARCH_PAUSE_MS = 500L
        private val DIRECT_IDS = setOf("buttons", "kids")
    }
}

/** One section: its shared rows from the schema, the companion's own rows, then Do now (§5.5). */
open class SettingsSectionActivity : SleepPickerPage() {
    protected open val fixedSection: String? = null
    private val sectionId: String get() = fixedSection ?: intent.getStringExtra(EXTRA_SECTION) ?: "reading"
    override val loadsChoices: Boolean get() = sectionId == "sleep"
    private var focus: String? = null
    private var testResult: String? = null
    private var test: NetTest? = null
    private var restartNeeded = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (fixedSection == null && !intent.hasExtra(EXTRA_SECTION)) {
            val last = getSharedPreferences("settings_ui", MODE_PRIVATE).getString("section", null)
            intent.putExtra(EXTRA_SECTION, last?.takeIf { schema.section(it) != null } ?: "reading")
        }
        getSharedPreferences("settings_ui", MODE_PRIVATE).edit().putString("section", sectionId).apply()
        focus = intent.getStringExtra(EXTRA_FOCUS)
    }

    override fun onResume() {
        super.onResume()
        getSharedPreferences("settings_ui", MODE_PRIVATE).edit().putString("section", sectionId).apply()
    }

    /** After an update from this section: the same section, at the App version row ("Updated to v…"). */
    override fun returnIntent(): Intent = super.returnIntent().apply {
        if (getStringExtra(EXTRA_FOCUS) == null && SettingsUi.extras(sectionId).any { it.id == UPDATE_ROW }) putExtra(EXTRA_FOCUS, UPDATE_ROW)
    }

    override fun onPause() {
        super.onPause()
        test?.cancel()
    }

    private val addon: Boolean get() = prefs.mode == OrbitMode.ADDON

    override fun render() {
        val root = page(scroll = true)
        val section = schema.section(sectionId)
        root.addView(Ui.header(this, section?.title ?: "Settings", "‹ Settings") { finish() })
        lockedBar(root)
        val extras = SettingsUi.extras(sectionId)
        val focused = mutableListOf<View>()
        fun extra(e: SettingsUi.Extra) {
            val before = root.childCount
            drawExtra(root, e.id)
            if (e.id == focus && root.childCount > before) focused += root.getChildAt(before)
        }
        // A section's companion rows that lead (Home opens before the Home button, the helpers).
        schema.settings.filter { it.section == sectionId }.forEach { d ->
            extras.filter { it.before == d.key && !it.action }.forEach { extra(it) }
            SettingsSlots.draw(this, sectionId, root, locked, before = d.key)
            val before = root.childCount
            drawShared(root, d)
            if (d.key == focus && root.childCount > before) focused += root.getChildAt(before)
        }
        extras.filter { it.before == null && !it.action }.forEach { extra(it) }
        SettingsSlots.draw(this, sectionId, root, locked)
        val actions = extras.filter { it.action }
        if (!locked && (actions.isNotEmpty() || restartNeeded)) {
            subhead(root, "Do now")
            if (restartNeeded) root.addView(Ui.button(this, "Restart KOReader to apply", heightDp = 56, sp = 20f) {
                Koreader.restart(this, "settings: restart to apply")
                restartNeeded = false
            })
            actions.forEach { extra(it) }
            testResult?.let { root.addView(Ui.text(this, it, 18f).apply { setPadding(0, Ui.dp(this@SettingsSectionActivity, 8), 0, 0) }) }
        }
        // The searched row: outlined, at the top of the page.
        focused.firstOrNull()?.let { v ->
            v.foreground = Ui.box(this, android.graphics.Color.TRANSPARENT, strokeDp = 2, radiusDp = 2)
            v.post { (root.parent as? android.widget.ScrollView)?.scrollTo(0, v.top) }
        }
    }

    /** A shared key's row, by its type (§5.5): toggles, segmented up to four values, else a page. */
    private fun drawShared(root: LinearLayout, d: SettingDef) {
        if (d.hidden) return
        if (d.cap != null && d.cap !in Mode.caps(this)) return
        if (d.key == "home_button" && (addon || !HomeApp.showsHomeButton(prefs.homeApp))) return
        val get = { k: String -> SettingsStore.get(this, k) }
        if (!SettingsSync.visible(schema, d.key, get)) return
        val v = get(d.key)
        val line = lineFor(d)
        // The page's title already names it (Sleep screen's own choice): shown once.
        val label = d.label.takeIf { it != schema.section(sectionId)?.title }
        when {
            d.key == "update_channel" -> {
                root.addView(Ui.text(this, d.label, 21f))
                val descriptions = listOf("tested releases only", "also release candidates, about to become stable", "every test build")
                val channels = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; tag = "key:${d.key}" }
                root.addView(channels)
                d.values.forEachIndexed { i, (key, title) ->
                    Ui.row(this, title, descriptions[i], Ui.value(this, if (v == key) "●" else "○"),
                        onClick = if (locked) null else ({ setShared(d.key, key) })).also {
                        it.tag = "channel:$key"
                        channels.addView(it)
                    }
                }
            }
            d.type == "bool" -> toggleRow(root, d.label, line, v == "1") { on ->
                // Merged rows (§5.2): one switch sets the companion's half too.
                when (d.key) {
                    "wake_tailscale" -> prefs.wakeTailscaleWithWifi = on
                    "auto_update_patch" -> prefs.autoUpdate = on
                }
                if (d.applies == "restart") restartNeeded = true
                setShared(d.key, if (on) "1" else "0")
            }.tag = "key:${d.key}"
            d.type == "choice" && d.values.size <= 4 -> {
                val before = root.childCount
                segmented(root, label, line, d.values.map { (id, _) -> id to d.valueLabel(id) }, v) { setShared(d.key, it) }
                root.getChildAt(before)?.tag = "key:${d.key}"
            }
            d.type == "choice" || d.type == "source" -> linkRow(root, d.label, line, SettingsUi.valueLabel(d, v, choices) + "  ›") {
                startActivity(Intent(this, SettingChoiceActivity::class.java).putExtra(EXTRA_KEY, d.key))
            }.tag = "key:${d.key}"
            d.type == "rules" -> linkRow(root, d.label, line, SettingsUi.valueLabel(d, v) + "  ›") {
                startActivity(Intent(this, LeaveOutActivity::class.java))
            }.tag = "key:${d.key}"
            d.type == "text" -> Ui.row(this, d.label, line, Ui.value(this, if (locked) SettingsUi.valueLabel(d, v) else "Edit"),
                onClick = if (locked) null else ({ editText(d, v) })).also {
                if (v.isNotEmpty()) (it.getChildAt(0) as? LinearLayout)?.addView(Ui.text(this, v, 18f, bold = true))
                it.tag = "key:${d.key}"
                root.addView(it)
            }
        }
    }


    /** A one-line text, "12 of 60" under it. */
    private fun editText(d: SettingDef, v: String) {
        val count = Ui.text(this, "", 16f, color = Ui.MID)
        val input = Ui.input(this).apply {
            setText(v)
            setSingleLine()
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            filters = arrayOf(InputFilter.LengthFilter(d.max * 2))
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, c: Int, after: Int) = Unit
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, c: Int) = Unit
                override fun afterTextChanged(s: Editable?) {
                    val t = s?.toString().orEmpty()
                    count.text = "${t.codePointCount(0, t.length)} of ${d.max}"
                }
            })
        }
        count.text = "${v.codePointCount(0, v.length)} of ${d.max}"
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val p = Ui.dp(this@SettingsSectionActivity, 16)
            setPadding(p, p / 2, p, 0)
            addView(input)
            addView(count)
        }
        AlertDialog.Builder(this).setTitle(d.label).setView(box)
            .setPositiveButton("Save") { _, _ -> setShared(d.key, input.text.toString()) }
            .setNeutralButton("Clear") { _, _ -> setShared(d.key, "") }
            .setNegativeButton("Cancel", null).show()
    }

    /** The companion's own rows, by id (SettingsUi.EXTRAS). */
    private fun drawExtra(root: LinearLayout, id: String) {
        val ro = locked
        when (id) {
            "home_opens" -> if (!addon) {
                val c = prefs.homeApp
                linkRow(root, "Home opens", HomeApp.summary(c, if (HomeApp.isApp(c)) HomeTarget.label(this, c) else null)) {
                    startActivity(Intent(this, HomeAppActivity::class.java))
                }
            }
            "helper_wifi" -> helper(root, "Wi-Fi switching", "BookSync turns Wi-Fi on for a sync and off again", prefs.helperWifi) { prefs.helperWifi = it }
            "helper_sleep_sync" -> helper(root, "Sleep sync", "keeps the reader awake while it syncs on sleep", prefs.helperSleepSync) { prefs.helperSleepSync = it }
            "screen_off" -> if (addon && prefs.helperSleepSync) {
                helper(root, "Screen off after Sync and sleep", if (Net.adminActive(this)) "uses the lock-screen permission" else "asks for the lock-screen permission", prefs.helperScreenOff) {
                    prefs.helperScreenOff = it
                    if (it && !Net.adminActive(this)) {
                        tryStart(
                            Intent(android.app.admin.DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                                .putExtra(android.app.admin.DevicePolicyManager.EXTRA_DEVICE_ADMIN, AdminReceiver.component(this))
                                .putExtra(android.app.admin.DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Lets \"Sync and sleep\" turn the screen off after syncing. It uses only the lock-screen permission."),
                            "device admin",
                        )
                    }
                }
            }
            "wifi_after_sleep" -> if ((!addon || prefs.helperSleepSync) && SettingsStore.get(this, "sync_on_sleep") == "1") {
                segmented(root, "Wi-Fi after sleep sync", "Short naps keep Wi-Fi up, so waking syncs in about 1 s. The timer only turns Wi-Fi off if the screen is still off.",
                    listOf(WifiAfterSleep.KEEP_ON to "Keep on", WifiAfterSleep.OFF_AFTER_30 to "Off after 30 min", WifiAfterSleep.OFF_NOW to "Off now"), prefs.wifiAfterSleep) {
                    prefs.wifiAfterSleep = it
                    companionChanged("wifi_after_sleep=${it.key}")
                }
            }
            "wake_lock" -> if ((!addon || prefs.helperSleepSync) && SettingsStore.get(this, "sync_on_sleep") == "1") {
                toggleRow(root, "Keep the reader awake while syncing", "Released at the plugin's 20 s cap; 25 s at most.", prefs.wakeLockEnabled) {
                    prefs.wakeLockEnabled = it
                    companionChanged("wake_lock=$it")
                }
            }
            "notify_tailscale" -> toggleRow(root, "Tailscale alert", "A notification when Tailscale won't connect.", prefs.notifyTailscale) {
                prefs.notifyTailscale = it
                companionChanged("notify_tailscale=$it")
            }
            "helper_clicker" -> helper(root, "Clicker buttons", "Bluetooth page clicker buttons", prefs.helperClicker) { prefs.helperClicker = it }
            "clickers" -> if (!addon || prefs.helperClicker) {
                linkRow(root, "Clicker buttons", "Bluetooth page clicker: page turns, Home, Back, Sleep") { startActivity(Intent(this, ClickersActivity::class.java)) }
            } else root.addView(note("Without the Clicker buttons helper, clicker buttons are KOReader's own."))
            "helper_pin" -> helper(root, "Settings PIN", "locks BookSync's settings (not your launcher's)", prefs.helperPin) { prefs.helperPin = it }
            "pin" -> when {
                addon && !prefs.helperPin -> Unit
                Pin.isSet(this) -> {
                    linkRow(root, "Settings PIN", "On · tap to change") { Pin.run(this) { startActivity(PinActivity.intent(this, PinActivity.Mode.SET)) } }
                    if (!ro) linkRow(root, "Turn the PIN off", null) {
                        Pin.run(this) {
                            Pin.clear(this, "turned off in Settings")
                            render()
                        }
                    }
                }
                else -> linkRow(root, "Settings PIN", "Off · keeps kids out of settings") { startActivity(PinActivity.intent(this, PinActivity.Mode.SET)) }
            }
            "guarded" -> if ((!addon || prefs.helperPin) && Pin.isSet(this)) {
                linkRow(root, "Guarded apps", "${Pin.guarded(this).size} · open only after the PIN") { Pin.run(this) { startActivity(Intent(this, GuardedAppsActivity::class.java)) } }
            }
            "reminders" -> root.addView(Ui.row(this, "Reminders", "Set reminders in BookSync reader settings"))
            "reading_statistics" -> linkRow(root, "Reading statistics", "Local goal and explicit completions · This reader only") { startActivity(Intent(this, LocalReadingSettingsActivity::class.java)) }
            "setup" -> linkRow(root, "Setup", "The checklist: what BookSync needs on this reader") { startActivity(Intent(this, SetupActivity::class.java)) }
            "mode" -> linkRow(root, "Mode", when (prefs.mode) {
                OrbitMode.ADDON -> "Add-on: your launcher stays · Switch"
                OrbitMode.FULL -> "Full: BookSync runs the reader · Switch"
                null -> "not chosen yet"
            }) { Pin.run(this) { startActivity(Intent(this, ModeActivity::class.java)) } }
            "recommended" -> {
                val r = RecommendedPages.read()
                val n = r?.items?.count { it.state == "conflict" } ?: 0
                linkRow(root, "Recommended settings", when {
                    r == null -> "Open KOReader once to see them here."
                    n > 0 -> "$n differ from BookSync's"
                    else -> "${r.items.count { it.state == "applied" }} applied"
                }) { startActivity(Intent(this, RecommendedReviewActivity::class.java)) }
            }
            "skipped" -> prefs.setupIgnored.takeIf { it.isNotEmpty() }?.let { skipped ->
                Ui.row(this, "Skipped setup steps: ${skipped.size}", "tap to be asked again", Ui.value(this, "›"), onClick = if (ro) null else ({
                    Attention.unignoreAll(this)
                    Attention.evaluate(this, "settings")
                    render()
                })).also { root.addView(it) }
            }
            "app_version" -> {
                val ready = Updater.readyToInstall()
                if (ready != null) {
                    root.addView(Ui.row(this, "App version", "Update ready: v${Version.parse(ready.first)?.display() ?: ready.first}", Ui.button(this, "Install", heightDp = 56, sp = 18f) {
                        startActivity(PinActivity.thenInstall(this, ready.second))
                    }))
                } else {
                    root.addView(Ui.row(this, "App version", Updater.statusLine(this), Ui.button(this, if (Updater.busy) "Checking…" else "Check for updates", heightDp = 56, sp = 18f) {
                        Pin.run(this) {
                            Updater.check(this, interactive = true, why = "settings") { if (!isFinishing) render() }
                            render()
                        }
                    }))
                }
            }
            "debug_log" -> toggleRow(root, "Debug log", "More detail in logcat, tag OrbitCompanion.", prefs.debugLog) {
                prefs.debugLog = it
                companionChanged("debug=$it")
            }
            "details" -> linkRow(root, "Details", "Versions and state, for support") { startActivity(Intent(this, SetupDetailsActivity::class.java)) }
            "licenses" -> linkRow(root, "Open-source licenses", null) { startActivity(Intent(this, LicensesActivity::class.java)) }
            "shown_by" -> if (SettingsStore.get(this, "sleep_mode") != "off") {
                linkRow(root, "Shown by", SleepScreen.shownBy(this)) { SleepSetupHelp.setUp(this) { render() } }
            }
            "preview" -> if (SettingsStore.get(this, "sleep_mode") != "off") {
                linkRow(root, "Preview", "5 s, or until you tap") { startActivity(Intent(this, SleepPreviewActivity::class.java)) }
            } else root.addView(note("The reader shows its own sleep screen. Turn this on for a recommended library cover or the current book."))
            "do_sync_sleep" -> command("Sync and sleep now", HomeCommands.SYNC_SLEEP, root)
            "do_test_sync_path" -> command("Test the sync path", HomeCommands.TEST_SYNC_PATH, root)
            "do_full_refresh" -> command("Full refresh now", HomeCommands.FULL_REFRESH, root)
            "do_test_network" -> root.addView(Ui.button(this, if (test?.running == true) "Testing…" else "Test network", heightDp = 56, sp = 20f) { runTest() }.withGap())
        }
    }

    private fun View.withGap(): View = apply {
        layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = Ui.dp(this@SettingsSectionActivity, 8) }
    }

    /** A Do now button: KOReader does the work, so it starts with the COMMAND (when its plugin knows it). */
    private fun command(label: String, cmd: String, root: LinearLayout) {
        root.addView(Ui.button(this, label, heightDp = 56, sp = 20f) {
            val plugin = prefs.patchVersionSeen.ifEmpty { null }
            if (PluginCommands.allowed(cmd, plugin) == null) {
                Ui.note(this, "This needs a newer BookSync plugin in KOReader. Install this app's update in Setup, then try again.")
            } else {
                Koreader.start(this, "settings: $label", cmd)
            }
        }.withGap())
    }

    private fun runTest() {
        if (test?.running == true) return
        testResult = "Testing: Wi-Fi on, Tailscale wake…"
        test = NetTest(this, offFirst = false) { ok, summary ->
            testResult = (if (ok) "Network test passed: " else "Network test failed: ") + summary
            render()
        }.also { it.start() }
        render()
    }

    /** An Add-on helper, shown only in Add-on: starts or stops the service and tells the plugin. */
    private fun helper(root: LinearLayout, label: String, sub: String, on: Boolean, set: (Boolean) -> Unit) {
        if (!addon) return
        toggleRow(root, label, sub, on) {
            set(it)
            Mode.helpersChanged(this, "helper $label ${if (it) "on" else "off"}")
            render()
        }
    }

    private fun companionChanged(what: String) {
        OLog.debug = prefs.debugLog
        OLog.i("settings: $what")
        OrbitService.start(this, Intent(OrbitService.ACTION_REFRESH))
        render()
    }
}

/**
 * Rows other features add to a section without editing it, e.g. "Sharp covers: sign in once" in
 * Sleep screen (docs/design/companion-settings.md §6). Drawn after the section's own rows.
 */
object SettingsSlots {
    fun interface Slot {
        fun draw(a: SettingsPage, root: LinearLayout, locked: Boolean)
    }

    private data class Entry(val section: String, val before: String?, val slot: Slot)

    private val slots = mutableListOf(Entry("sleep", "sleep_from", ScreenModeRow), Entry("sleep", "sleep_text", SharpCoversRow))

    /** [before]: drawn just before that shared key's place (whether or not it shows); null: after the section's rows. */
    @Synchronized
    fun register(section: String, before: String? = null, slot: Slot) { slots += Entry(section, before, slot) }

    @Synchronized
    fun draw(a: SettingsPage, section: String, root: LinearLayout, locked: Boolean, before: String? = null) {
        slots.filter { it.section == section && it.before == before }.forEach {
            runCatching { it.slot.draw(a, root, locked) }.onFailure { e -> OLog.w("settings slot in $section", e) }
        }
    }
}

/** A choice with five or more values, or the sleep screen's Pick from (§5.5, §6.1). */
class SettingChoiceActivity : SleepPickerPage() {
    private val key: String get() = intent.getStringExtra(EXTRA_KEY).orEmpty()
    override val loadsChoices: Boolean get() = schema.byKey[key]?.type == "source"

    override fun render() {
        beginPicker()
        val d = schema.byKey[key] ?: return finish()
        val root = page(scroll = true)
        root.addView(Ui.header(this, d.label, "‹ Back") { finish() })
        lockedBar(root)
        root.addView(pickerNote(d))
        val v = SettingsStore.get(this, key)
        fun option(id: String, label: String, sub: String? = null) {
            val sel = id == v
            root.addView(Ui.row(this, (if (sel) "●  " else "○  ") + label, sub, onClick = if (locked || sel) null else ({ setShared(key, id); finish() })).apply { tag = "option:$id" })
        }
        if (d.type != "source") {
            d.values.forEach { (id, label) -> option(id, label) }
            return
        }
        // Pick from is a set (docs/design/lock-screen.md R1c): each item ticks on and off, the page stays.
        val picked = SleepPoolLogic.sources(v)
        fun tick(id: String, label: String, sub: String? = null) {
            pickerRow(root, id, label, sub, id in picked, "option:$id") {
                val current = SettingsStore.get(this, key)
                val missing = id.contains(':') && choices?.title(id) == null && id in SleepPoolLogic.sources(current)
                setPicked(key, if (missing) SleepPoolLogic.sources(current).filter { it != id }.joinToString("\n") else SleepPoolLogic.togglePick(current, id))
            }
        }
        tick(SleepPoolLogic.LIBRARY, "Whole library", "Every book you can see, OR pick sources below.")
        subhead(root, "Pick sources")
        d.values.filter { it.first != SleepPoolLogic.LIBRARY }.forEach { (id, label) -> tick(id, label) }
        val c = choices
        if (c == null) {
            root.addView(note("Open KOReader once to load your lists and collections."))
        } else {
            if (c.libraries.isNotEmpty()) subhead(root, "Libraries")
            c.libraries.forEach { tick("library:${it.id}", it.title, it.count?.let { n -> "$n books" }) }
            if (c.scopes.isNotEmpty()) subhead(root, "Lists")
            c.scopes.forEach { tick("scope:${it.id}", it.title, it.count?.let { n -> "$n books" }) }
            if (c.collections.isNotEmpty()) subhead(root, "Collections")
            c.collections.forEach { tick("collection:${it.id}", it.title, it.count?.let { n -> "$n books" }) }
            if (c.at > 0) root.addView(note("Lists from library, ${Ui.clock(this, c.at)}"))
        }
        picked.filter { (it.startsWith("scope:") || it.startsWith("collection:") || it.startsWith("library:")) && c?.title(it) == null }.forEach { tick(it, c?.missingLabel(it) ?: SleepChoices.fallback(it), "Tap to drop this source") }
        root.addView(note("For a custom field: make a list with that condition in library, then pick it here."))
    }
}

/** Sleep screen › Leave out: every rule toggles in place, including tags typed by the reader. */
class LeaveOutActivity : SleepPickerPage() {
    override fun render() {
        beginPicker()
        val d = schema.byKey["sleep_leave_out"] ?: return finish()
        val c = choices
        val rules = SleepPoolLogic.rules(SettingsStore.get(this, d.key))
        val root = page(scroll = true)
        root.addView(Ui.header(this, "Leave out", "‹ Back") { finish() })
        lockedBar(root)
        root.addView(pickerNote(d))
        fun toggle(rule: String) {
            // Choosing an individual rule explicitly replaces the all-books selection.
            val current = SleepPoolLogic.rules(SettingsStore.get(this, d.key))
            val base = if (rule != SleepPoolLogic.LIBRARY) current - SleepPoolLogic.LIBRARY else current
            setPicked(d.key, SleepPoolLogic.toggleRule(base.joinToString("\n"), rule))
        }
        fun tick(rule: String, label: String, sub: String? = null) {
            pickerRow(root, rule, label, sub, rule in rules, "pick:$rule") { toggle(rule) }
        }
        if (SleepPoolLogic.LIBRARY in rules) {
            linkRow(root, "Remove old whole-library exclusion", "Choose the libraries to leave out below.") {
                setPicked(d.key, "")
                render()
            }
        }
        subhead(root, "Tags")
        if (!locked) linkRow(root, "Type a tag…", null) { typeTag { if ("tag:$it" !in SleepPoolLogic.rules(SettingsStore.get(this, d.key))) toggle("tag:$it") } }
        c?.tags?.forEach { t -> tick("tag:${t.tag}", t.label, "${t.count} books") }
        rules.filter { it.startsWith("tag:") && c?.tags?.none { t -> "tag:${t.tag}" == it } != false }
            .forEach { tick(it, c?.missingLabel(it) ?: SleepChoices.fallback(it), "Tap to drop this source") }
        if (c == null) root.addView(note("Open KOReader once to load your tags, lists and collections."))
        if (c?.libraries?.isNotEmpty() == true) subhead(root, "Libraries")
        c?.libraries?.forEach { tick("library:${it.id}", it.title, it.count?.let { n -> "$n books" }) }
        if (c?.scopes?.isNotEmpty() == true) subhead(root, "Lists")
        c?.scopes?.forEach { tick("scope:${it.id}", it.title, it.count?.let { n -> "$n books" }) }
        if (c?.collections?.isNotEmpty() == true) subhead(root, "Collections")
        c?.collections?.forEach { tick("collection:${it.id}", it.title, it.count?.let { n -> "$n books" }) }
        rules.filter { (it.startsWith("scope:") || it.startsWith("collection:") || it.startsWith("library:")) && c?.title(it) == null }
            .forEach { tick(it, c?.missingLabel(it) ?: SleepChoices.fallback(it), "Tap to drop this source") }
        root.addView(note("For a custom field: make a list with that condition in library, then leave it out here."))
    }

    private fun typeTag(done: (String) -> Unit) {
        val input = Ui.input(this).apply { setSingleLine(); hint = "age:18" }
        AlertDialog.Builder(this).setTitle("Tag").setView(input)
            .setPositiveButton("Add") { _, _ -> SleepPoolLogic.parseRule("tag:${input.text}")?.tag?.let(done) }
            .setNegativeButton("Cancel", null).show()
    }
}

object RecommendedPages {
    fun file(): File = File(Environment.getExternalStorageDirectory(), "koreader/settings/${RecommendedReview.FILE}")

    fun read(): RecommendedReview? = RecommendedReview.parse(runCatching { file().readText() }.getOrNull())
}

/** Setup and mode › Recommended settings: the plugin's review list; KOReader applies the choices (§5.8). */
class RecommendedReviewActivity : SettingsPage() {
    override fun render() {
        val root = page(scroll = true)
        root.addView(Ui.header(this, "Recommended settings", "‹ Back") { finish() })
        lockedBar(root)
        val r = RecommendedPages.read()
        if (r == null) {
            root.addView(note("Open KOReader once: the BookSync plugin lists its recommended settings here."))
            return
        }
        val queued = SettingsStore.get(this, "recommended_choice")
        root.addView(note("KOReader applies your choices when it next starts or wakes, because they are KOReader's and library's own settings." +
            if (r.at > 0) " List from KOReader, ${Ui.clock(this, r.at)}." else ""))
        r.items.forEach { it0 ->
            val q = SettingsUi.choiceFor(queued, it0.id)?.takeIf { it in it0.offers }
            val sub = it0.stateLine + (q?.let { " … ${RecommendedReview.CHOICE_WORDS[it]}: waiting for KOReader" } ?: "")
            val buttons = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            if (!locked && q == null) it0.offers.forEach { what ->
                buttons.addView(Ui.button(this, RecommendedReview.CHOICE_WORDS.getValue(what), heightDp = 56, sp = 16f) { choose(it0.id, what) },
                    LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { marginStart = Ui.dp(this@RecommendedReviewActivity, 6) })
            }
            root.addView(Ui.row(this, it0.label, sub, buttons).apply { tag = "rec:${it0.id}" })
        }
        if (!locked && r.items.any { it.state == "conflict" } && queued.isEmpty()) {
            root.addView(Ui.gap(this, 12))
            root.addView(Ui.button(this, "Use BookSync's for all", heightDp = 56, sp = 20f) { choose("all", "ours") })
        }
    }

    private fun choose(id: String, what: String) {
        setShared("recommended_choice", SettingsUi.withChoice(SettingsStore.get(this, "recommended_choice"), id, what))
    }
}

/** Sleep screen's Shown by row (docs/design/lock-screen.md P1-P3): choose Orbit's screen saver, or say how. */
object SleepSetupHelp {
    fun setUp(a: EinkActivity, redraw: () -> Unit) {
        when (SleepScreen.sink(a)) {
            SleepSink.DREAM -> when {
                SleepScreen.oursChosen(a) -> Ui.note(a, "BookSync's screen saver shows the sleep screen.")
                SleepScreen.chooseOurs(a, "Set up") -> redraw()
                !a.tryStart(Intent(android.provider.Settings.ACTION_DREAM_SETTINGS), "screen saver settings") -> Ui.note(a,
                    "This reader hides its Screen saver settings. Connect it to a computer and run:\n\ntools/install-usb.sh --sleep-screen on\n\n" +
                        "or, once, tools/install-usb.sh --grant-screen-saver so BookSync can switch it itself.")
            }
            SleepSink.PICTURE -> Ui.note(a,
                "On the reader: Apps › Screensaver › Screensaver style, pick the picture Pictures/Orbit/sleep.png. BookSync keeps it up to date.")
        }
    }
}
