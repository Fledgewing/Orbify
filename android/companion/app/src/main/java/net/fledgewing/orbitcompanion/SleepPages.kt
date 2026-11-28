package net.fledgewing.orbitcompanion

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout

/**
 * Settings › Sleep screen (docs/design/lock-screen.md S1, S2; companion-settings §6): the section
 * page for the shared sleep-screen keys, also opened by KOReader's menu (SHOW_SLEEP). Read-only
 * behind the Settings PIN (K1).
 */
class SleepScreenActivity : SettingsSectionActivity() {
    override val fixedSection: String = "sleep"
}

/**
 * L7: Sharp covers, the Sleep screen section's row (docs/design/sharp-sleep-covers, through
 * SettingsSlots): signed in once, or the thumbnail fallback (a state, not a mode). Shown for
 * Recommended cover, after Change cover every.
 */
/**
 * Onboarding's optional screen-mode step (ScreenModeSetup), right after the sleep screen is
 * chosen, until marked done: the Sleep screen section's slot after its first row.
 */
object ScreenModeRow : SettingsSlots.Slot {
    override fun draw(a: SettingsPage, root: LinearLayout, locked: Boolean) {
        val mode = SleepScreen.settings(a).mode
        ScreenModeSetup.row(mode, ScreenModeSetup.way(a))?.takeIf { !it.done }?.let { r ->
            root.addView(Ui.row(a, "${r.label} (optional)", "${r.stateLine}\nWithout it: ${Checklist.LOSS.getValue(ScreenModeSetup.ID)}",
                Ui.value(a, "How ›"), onClick = if (locked) null else ({ ScreenModeSetup.how(a) })).apply { tag = "slot:screen_mode" })
        }
    }
}

object SharpCoversRow : SettingsSlots.Slot {
    override fun draw(a: SettingsPage, root: LinearLayout, locked: Boolean) {
        if (SettingsStore.get(a, "sleep_mode") != "recommended") return
        val acct = SharpCovers.account()
        val state = SharpCovers.state(a)
        val ids = SleepScreen.pool().map { it.id }
        val (sub, value) = SharpCoversLogic.row(state, acct != null, SharpCovers.sharpCount(a, ids), ids.size, SharpCovers.lostWhy(a))
        root.addView(Ui.row(a, SharpCoversLogic.TITLE, sub, if (value.isEmpty()) null else Ui.value(a, value), onClick = when {
            acct == null || locked -> null
            state == SharpCoversLogic.State.ON -> { -> signOutAsk(a) }
            else -> { -> signIn(a, acct) }
        }).apply { tag = "slot:sharp_covers" })
    }

    private fun signOutAsk(a: SettingsPage) {
        android.app.AlertDialog.Builder(a)
            .setMessage("Sleep-screen covers come from library's full-size cover. Sign out to use the small thumbnail again.")
            .setPositiveButton("Sign out") { _, _ -> SharpCovers.signOut(a, "companion page"); a.render() }
            .setNegativeButton("Keep", null).show()
    }

    /** The OPDS login, once: the password goes to one request and is cleared; only the cover link is kept. */
    private fun signIn(a: SettingsPage, acct: SharpCovers.Account) {
        val pad = Ui.dp(a, 16)
        val user = Ui.input(a).apply {
            hint = "OPDS username"
            setText(SharpCovers.user(a) ?: acct.user)
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
        }
        val pass = Ui.input(a).apply {
            hint = "OPDS password"
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
        }
        val box = LinearLayout(a).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad / 2, pad, 0)
            addView(Ui.text(a, SharpCoversLogic.PROMPT, 16f, color = Ui.MID))
            addView(user)
            addView(pass)
        }
        android.app.AlertDialog.Builder(a).setTitle(SharpCoversLogic.TITLE).setView(box)
            .setPositiveButton("Sign in") { _, _ ->
                val name = user.text.toString().trim()
                val e = pass.text
                val pw = CharArray(e.length).also { e.getChars(0, e.length, it, 0) }
                e.clear()
                kotlin.concurrent.thread(name = "orbit-sharp-sign-in") {
                    val msg = SharpCovers.signIn(a, acct.server, name, pw)
                    if (msg == null) SharpCovers.sync(a, "signed in")
                    a.runOnUiThread {
                        if (a.isFinishing) return@runOnUiThread
                        a.render()
                        Ui.note(a, msg ?: "Signed in. Sharp covers download now while the reader is online.")
                    }
                }
            }
            .setNegativeButton("Cancel") { _, _ -> pass.text.clear() }
            .show()
    }
}

/**
 * The preview (S2): the sleep screen as it would show now, for 5 s or until a tap. Opened from
 * KOReader's menu (SLEEP_PREVIEW) or the page above: a user action, so the reading gate allows it.
 * It never moves the rotation on.
 */
class SleepPreviewActivity : EinkActivity() {
    private val main = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val (w, h, dpi) = SleepScreen.panel(this)
        val bmp = SleepScreen.render(this, w, h, dpi, advance = false, why = "preview")
        val view = ImageView(this).apply {
            setBackgroundColor(android.graphics.Color.WHITE)
            scaleType = ImageView.ScaleType.FIT_CENTER
            setImageBitmap(bmp)
            setOnClickListener { finish() }
        }
        setContentView(view)
        main.postDelayed({ if (!isFinishing) finish() }, 5_000)
    }

    override fun onDestroy() {
        main.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}

/**
 * Setup's screen-saver row (docs/design/lock-screen.md P1-P3, companion-checklist §3.3). What the
 * USB-granted permission (WRITE_SECURE_SETTINGS) really does: when Sleep screen is turned on, Orbit
 * makes its own screen saver the reader's, and when it is turned off, puts the reader's own back
 * (SleepScreen.chooseOurs / restoreVendor). Without it nothing else changes: once Orbit's screen
 * saver is chosen (the USB command, or the reader's Screen saver page), the sleep screen works.
 *
 * So the row shows only when it helps on this reader right now (M8C feedback, 2026-11-24): the
 * reader uses a screen saver, Orbit can't switch it itself, the reader has no Screen saver page to
 * do it by hand, and what it shows while asleep doesn't match the Sleep screen setting (on, but
 * the reader's own screen saver is still chosen; or off, but Orbit's still is). Otherwise hidden.
 */
object SleepSetup {
    /** The checklist's id for it (Checklist.GROUP_OF, its "Without it:" line). */
    const val ID = "screen_saver"
    const val TITLE = "Screen saver"
    const val GRANT = "tools/install-usb.sh --grant-screen-saver"

    /** What the reader shows while asleep doesn't follow Sleep screen, and Orbit can't fix that itself. */
    fun shown(mode: SleepMode, sink: SleepSink, granted: Boolean, oursChosen: Boolean, hasSystemPage: Boolean): Boolean =
        sink == SleepSink.DREAM && !granted && !hasSystemPage && (mode != SleepMode.OFF) != oursChosen

    /** The state line: what is wrong now, in plain words. */
    fun stateLine(mode: SleepMode): String = if (mode != SleepMode.OFF) {
        "Sleep screen is on, but the reader still uses its own screen saver, so BookSync's cover doesn't show while it sleeps."
    } else {
        "Sleep screen is off, but BookSync's screen saver is still the reader's, so the reader's own sleep screen doesn't show."
    }

    /** "Show how": the one-time USB command for now, and the grant that makes it automatic. */
    fun how(mode: SleepMode): String {
        val now = "tools/install-usb.sh --sleep-screen ${if (mode != SleepMode.OFF) "on" else "off"}"
        return "This reader hides its Screen saver settings, so BookSync can't change what it shows while it sleeps. " +
            "Connect it to a computer and run, once:\n\n$now\n\n" +
            "Or run $GRANT once instead: then BookSync switches the screen saver itself whenever you turn Sleep screen on or off."
    }

    fun hasSystemPage(ctx: android.content.Context): Boolean =
        android.content.Intent(android.provider.Settings.ACTION_DREAM_SETTINGS).resolveActivity(ctx.packageManager) != null

    fun check(ctx: android.content.Context): Check? {
        val mode = SleepScreen.settings(ctx).mode
        if (!shown(mode, SleepScreen.sink(ctx), SleepScreen.canSwitch(ctx), SleepScreen.oursChosen(ctx), hasSystemPage(ctx))) return null
        return Check(TITLE, false, stateLine(mode), action = "Show how", optional = true, id = ID) { a ->
            OLog.i("setup: screen saver row: Show how (${mode.key})")
            Ui.note(a, how(mode))
        }
    }
}

/**
 * Setup's "Screen mode for Orbit" (docs/design/companion-checklist.md §3.3, lock-screen.md L10):
 * e-ink readers keep a per-app display mode, and a fast one leaves the last page ghosting through
 * the sleep screen. No Android API reads or sets it, so it is purely Optional (never counted,
 * walked or prompted) and finishes one of two ways: the user sets the mode and says so
 * ("I've set it"), or turns on the clearing flash instead (SleepFlash). Generic: no vendor names.
 * Shown while Sleep screen is on.
 */
object ScreenModeSetup {
    const val ID = "screen_mode"
    const val TITLE = "Screen mode for BookSync"
    const val HINT = "Set BookSync Companion to the reader's clearest screen mode (often called HD, Clear or Quality) " +
        "in its per-app display settings, so the sleep screen draws without ghosting."
    const val HOW = "Most e-ink readers let you pick a screen mode per app: a fast one for scrolling, a clear one for pictures.\n\n" +
        "Open the reader's per-app display or refresh settings (often from a floating button, the top menu, or Settings › Display), " +
        "choose BookSync Companion, and set it to the clearest mode (often called HD, Clear or Quality). BookSync can't see this " +
        "setting, so tap I've set it once it's done.\n\n" + SleepFlash.ABOUT
    const val SET = "I've set it"
    const val USE_FLASH = "Use a clearing flash instead"
    const val FLASH_ON = "On: the clearing flash runs before the cover."

    /** How the step was finished, if it was. */
    enum class Way { NONE, SET, FLASH }

    fun way(setDone: Boolean, flash: Boolean): Way = when {
        setDone -> Way.SET
        flash -> Way.FLASH
        else -> Way.NONE
    }

    /** Shown while the sleep screen is Orbit's (any mode but the reader's own). */
    fun shown(mode: SleepMode): Boolean = mode != SleepMode.OFF

    /** The row, or null when hidden. Always optional: left alone it only says "Without it: …". */
    fun row(mode: SleepMode, way: Way): Checklist.Row? = if (!shown(mode)) null else Checklist.Row(
        id = ID, label = TITLE, done = way != Way.NONE,
        stateLine = when (way) {
            Way.SET -> Checklist.optionalLine(ID, true).orEmpty()
            Way.FLASH -> FLASH_ON
            Way.NONE -> HINT
        },
        optional = true, verb = if (way == Way.NONE) "How" else null,
    )

    fun way(ctx: android.content.Context): Way = way(Prefs(ctx).screenModeDone, SleepScreen.settings(ctx).flash)

    fun check(ctx: android.content.Context): Check? {
        val r = row(SleepScreen.settings(ctx).mode, way(ctx)) ?: return null
        return Check(r.label, r.done, r.stateLine, action = r.verb, optional = true, id = ID) { a -> how(a) }
    }

    /** "I've set it": stored, since nothing can read the reader's mode. */
    fun markSet(ctx: android.content.Context) {
        Prefs(ctx).screenModeDone = true
        OLog.i("setup: screen mode: set by the user")
    }

    /** "Use a clearing flash instead": turns the flash on, which finishes the step too. */
    fun useFlash(ctx: android.content.Context) {
        val s = SleepScreen.settings(ctx)
        if (!s.flash) SleepScreen.save(ctx, s.copy(flash = true), "screen mode step", shared = true)
        OLog.i("setup: screen mode: clearing flash instead")
    }

    /** "How": the steps, then one of the two ways, or Skip. */
    fun how(a: EinkActivity) {
        OLog.i("setup: screen mode: How")
        android.app.AlertDialog.Builder(a).setTitle(TITLE).setMessage(HOW)
            .setPositiveButton(SET) { _, _ -> markSet(a); a.refresh() }
            .setNeutralButton(USE_FLASH) { _, _ -> useFlash(a); a.refresh() }
            .setNegativeButton("Skip", null).show()
    }
}
