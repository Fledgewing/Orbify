package net.fledgewing.orbitcompanion

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.os.Bundle
import android.text.format.DateFormat
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import java.util.Date
import java.util.Locale

/**
 * E-ink pages: black on white, no animations (theme + flags + overridePendingTransition),
 * no ripples (plain state-list backgrounds), big tap targets.
 */
abstract class EinkActivity : Activity() {
    companion object {
        @Volatile
        private var resumed = 0

        @Volatile
        private var lastPausedAt = 0L

        /** One of our pages is in front, or was until a moment ago (Home pauses it first). */
        fun companionPageInFront(): Boolean =
            resumed > 0 || android.os.SystemClock.elapsedRealtime() - lastPausedAt < 2_000

        /** One of our pages is resumed right now (no grace period: a Home press has paused it). */
        fun pageResumed(): Boolean = resumed > 0

        /** Our live pages, oldest first: the back stack an update returns to (UpdateReturn). */
        private val live = mutableListOf<java.lang.ref.WeakReference<EinkActivity>>()

        /**
         * The pages to rebuild after an update started on [top]: the live pages of its task up to
         * and including it, each as [returnIntent] (M8C 11-24: only the top page's class came
         * back, without its section, and Back from it fell out to KOReader).
         */
        @Synchronized
        fun returnStack(top: Activity): List<Intent> {
            val pages = live.mapNotNull { it.get() }.filter { !it.isDestroyed && !it.isFinishing && it.taskId == top.taskId && it.returnable }
            val below = if (pages.any { it === top }) pages.takeWhile { it !== top } else emptyList()
            val page = (top as? EinkActivity)?.returnIntent() ?: Intent().setComponent(top.componentName).apply { top.intent?.let { putExtras(it) } }
            return below.map { it.returnIntent() } + page
        }

        @Synchronized
        private fun track(a: EinkActivity, add: Boolean) {
            live.removeAll { it.get().let { p -> p == null || p === a } }
            if (add) live += java.lang.ref.WeakReference(a)
        }

        /** For tests: a fresh process. */
        @Synchronized
        internal fun forgetPages() {
            live.clear()
            resumed = 0
            lastPausedAt = 0
        }
    }

    /** This page can be reopened after an update (not the keypad or other transient pages). */
    open val returnable = true

    /** How to reopen this page after an update: its class and extras (a Settings section's id). */
    open fun returnIntent(): Intent = Intent().setComponent(componentName).apply { intent?.let { putExtras(it) } }

    /** Behind the Settings PIN: locked on resume → the keypad; cancel closes this page. */
    open val pinGuarded = false
    /** Showing an OPEN page ends an unlock (Pin.onPage). */
    open val pinPage: PinPage get() = if (pinGuarded) PinPage.PROTECTED else PinPage.OPEN
    private var pinAsked = false

    override fun onResume() {
        super.onResume()
        resumed++
        UpdateReturn.onPageShown(this)
        Pin.onPage(pinPage, javaClass.simpleName)
        // A companion page is in front: nobody is reading; what waited may show (Reading).
        Reading.onCompanionPage(this)
        if (pinGuarded && Pin.locked(this)) {
            if (pinAsked) return finish() // the keypad was cancelled
            pinAsked = true
            startActivity(PinActivity.intent(this, PinActivity.Mode.UNLOCK))
        } else {
            pinAsked = false
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setWindowAnimations(0)
        noTransition()
        track(this, add = true)
    }

    override fun onDestroy() {
        track(this, add = false)
        super.onDestroy()
    }

    override fun startActivity(intent: Intent, options: Bundle?) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
        super.startActivity(intent, options)
        noTransition()
    }

    override fun finish() {
        super.finish()
        noTransition()
    }

    override fun onPause() {
        super.onPause()
        resumed = maxOf(0, resumed - 1)
        lastPausedAt = android.os.SystemClock.elapsedRealtime()
        noTransition()
    }

    @Suppress("DEPRECATION")
    private fun noTransition() = overridePendingTransition(0, 0)

    /** Starts a system page; false (and logged) if this device has no such page. */
    fun tryStart(intent: Intent, what: String): Boolean = try {
        // Started while unlocked (a Setup Fix, a page from Settings): it joins the unlock.
        if (Pin.unlocked()) intent.resolveActivity(packageManager)?.packageName?.takeIf { it != packageName }?.let { Pin.opened(it) }
        startActivity(intent)
        OLog.i("opened $what")
        true
    } catch (e: Exception) {
        OLog.w("could not open $what", e)
        false
    }

    /** [scroll]: long pages (settings, setup) scroll; the rest are fixed, one e-ink redraw. */
    /** Re-render after an in-app fix finished (no onResume follows one). */
    open fun refresh() = Unit

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        @Suppress("DEPRECATION")
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (requestCode == Installers.PLUGIN_REQUEST_CODE) {
            OLog.i("plugin install: storage permission ${if (granted) "granted" else "denied"}")
            if (granted) Installers.plugin(this) { refresh() }
            else Prefs(this).pluginInstallStatus = "no storage permission: allow it, or copy the library connector plugin into the KOReader plugins folder (SETUP.md)"
            refresh()
            return
        }
        if (requestCode == FontInstaller.REQUEST_CODE) {
            OLog.i("reading fonts: storage permission ${if (granted) "granted" else "denied"}")
            if (granted) FontInstaller.set(this, true) { refresh() }
            else Prefs(this).fontsStatus = "no storage permission: allow it and tap Retry"
            refresh()
            return
        }
        if (requestCode != PatchInstaller.REQUEST_CODE) return
        OLog.i("patch install: storage permission ${if (granted) "granted" else "denied"}")
        if (granted) {
            PatchInstaller.install(this, userStarted = true) { refresh() }
        } else {
            Prefs(this).patchInstallStatus = "no storage permission: ${PatchInstaller.manualHint()}"
        }
        refresh()
    }

    /** The page's ScrollView, so a rebuild (a status change, Fix, a toggle) keeps the position. */
    private var scrollView: android.widget.ScrollView? = null

    /**
     * The page's root column. Every page scrolls (v0.5.5: the status page ran off the M8C's
     * screen below "Test network"); fillViewport keeps a short page full height. Only a page
     * that pages its own content by the height it gets passes scroll = false (UiPagesTest).
     * The page's header (Ui.header, a [HeaderBar]) is pinned above the scrolling part: the title
     * and its "‹ Back" stay at the top while the rows scroll (M8C feedback, 2026-11-24).
     */
    fun page(scroll: Boolean = true): LinearLayout {
        val keepY = scrollView?.scrollY ?: 0
        scrollView = null
        val p = Ui.dp(this, CompanionStyle.PAGE_INSET)
        val pinned = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Ui.PAPER)
            setPadding(p, Ui.dp(this@EinkActivity, 12), p, 0)
            tag = PINNED_TAG
        }
        val root = PageColumn(this, pinned).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Ui.PAPER)
            setPadding(p, 0, p, Ui.dp(this@EinkActivity, 12))
        }
        val frame = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Ui.PAPER)
            addView(pinned, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        val body: View = if (scroll) {
            android.widget.ScrollView(this).also {
                it.setBackgroundColor(Ui.PAPER)
                it.isVerticalScrollBarEnabled = true
                it.isFillViewport = true
                it.addView(root)
                scrollView = it
                // After layout, so the new content is tall enough; clamped by ScrollView itself.
                if (keepY > 0) it.post { it.scrollTo(0, keepY) }
            }
        } else root
        frame.addView(body, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(frame)
        return root
    }
}

/** The view that holds a page's pinned header (EinkActivity.page). */
const val PINNED_TAG = "page:pinned"

/** A page's header bar (Ui.header): the page column moves it into the pinned slot above the scroll. */
class HeaderBar(ctx: Context) : LinearLayout(ctx)

/** A page's root column: a [HeaderBar] added to it goes to [pinned] instead, so it never scrolls away. */
class PageColumn(ctx: Context, private val pinned: LinearLayout) : LinearLayout(ctx) {
    override fun addView(child: View?, index: Int, params: ViewGroup.LayoutParams?) {
        if (child is HeaderBar && child.parent == null) {
            pinned.addView(child, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            return
        }
        super.addView(child, index, params)
    }
}

/**
 * A list row (Ui.row): the text column, then the control, never overlapping. The control keeps a
 * fixed gap from the text and is capped at [Ui.CONTROL_MAX] of the row's width (a long value
 * wraps); the text column takes the rest and wraps (M8C feedback, 2026-11-24: "Applies when
 * KOReader restarts" ran into its switch).
 */
class RowLayout(ctx: Context) : LinearLayout(ctx) {
    var control: View? = null

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        (control as? TextView)?.let { c ->
            if (w > 0) c.maxWidth = (w * Ui.CONTROL_MAX).toInt()
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }
}

object Ui {
    const val INK = Color.BLACK
    const val PAPER = Color.WHITE
    val MID = Color.rgb(0x55, 0x55, 0x55)
    val LIGHT = Color.rgb(0xBB, 0xBB, 0xBB)
    val PRESSED = Color.rgb(0xDD, 0xDD, 0xDD)

    const val ROW_DP = 76
    /** A status row's height (Ui.row compact): read, rarely tapped. */
    const val INFO_ROW_DP = 64
    const val BUTTON_DP = 88
    /** The fixed gap between a row's text and its control. */
    const val ROW_GAP_DP = 16
    /** A row's control takes at most this share of the row's width. */
    const val CONTROL_MAX = 0.45f

    fun dp(ctx: Context, v: Int): Int = (v * ctx.resources.displayMetrics.density + 0.5f).toInt()

    fun box(ctx: Context, fill: Int, stroke: Int = INK, strokeDp: Int = 2, radiusDp: Int = CompanionStyle.CARD_RADIUS, oval: Boolean = false): GradientDrawable =
        GradientDrawable().apply {
            if (oval) shape = GradientDrawable.OVAL else cornerRadius = dp(ctx, radiusDp).toFloat()
            setColor(fill)
            if (strokeDp > 0) setStroke(dp(ctx, strokeDp), stroke)
        }

    /** Instant state change, no ripple, no fade. */
    fun pressable(normal: Drawable, pressed: Drawable): StateListDrawable = StateListDrawable().apply {
        addState(intArrayOf(android.R.attr.state_pressed), pressed)
        addState(intArrayOf(), normal)
        setEnterFadeDuration(0)
        setExitFadeDuration(0)
    }

    fun text(ctx: Context, s: CharSequence, sp: Float = 20f, bold: Boolean = false, color: Int = INK): TextView =
        TextView(ctx).apply {
            text = s
            setTextColor(color)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, CompanionStyle.textSize(ctx, sp))
            typeface = if (bold) CompanionStyle.strong else CompanionStyle.sans
            includeFontPadding = false
            setLineSpacing(0f, 1.15f)
        }

    /** Native form controls inherit the same body floor as every drawn row. */
    fun input(ctx: Context): android.widget.EditText = android.widget.EditText(ctx).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, CompanionStyle.textSize(ctx, CompanionStyle.BODY))
        typeface = CompanionStyle.sans
    }

    fun checkBox(ctx: Context, label: String): android.widget.CheckBox = android.widget.CheckBox(ctx).apply {
        text = label
        setTextSize(TypedValue.COMPLEX_UNIT_SP, CompanionStyle.textSize(ctx, CompanionStyle.BODY))
        typeface = CompanionStyle.sans
    }

    fun clickable(v: View, onClick: (() -> Unit)?, onLong: (() -> Unit)? = null) {
        v.isSoundEffectsEnabled = false
        v.isHapticFeedbackEnabled = false
        if (onClick != null) v.setOnClickListener { onClick() }
        if (onLong != null) v.setOnLongClickListener { onLong(); true }
    }

    fun button(ctx: Context, label: CharSequence, solid: Boolean = false, heightDp: Int = BUTTON_DP, sp: Float = 22f, radiusDp: Int = CompanionStyle.CARD_RADIUS, onClick: () -> Unit): TextView =
        text(ctx, label, sp, bold = true, color = if (solid) PAPER else INK).apply {
            gravity = Gravity.CENTER
            minHeight = dp(ctx, heightDp)
            val p = dp(ctx, if (radiusDp == CompanionStyle.FORM_RADIUS) CompanionStyle.FORM_BUTTON_INSET else 12)
            setPadding(p, p / 2, p, p / 2)
            background = if (solid) {
                pressable(box(ctx, INK, radiusDp = radiusDp), box(ctx, MID, radiusDp = radiusDp))
            } else {
                pressable(box(ctx, PAPER, radiusDp = radiusDp), box(ctx, PRESSED, radiusDp = radiusDp))
            }
            clickable(this, onClick)
        }

    /** Launcher secondary tile: outlined circle above its label, as in the approved launcher. */
    fun launcherTile(ctx: Context, symbol: String, label: String, onClick: () -> Unit): LinearLayout =
        LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            minimumHeight = dp(ctx, CompanionStyle.TILE_HEIGHT)
            background = pressable(box(ctx, PAPER), box(ctx, PRESSED))
            addView(text(ctx, symbol, 32f, bold = true).apply {
                gravity = Gravity.CENTER
                val size = dp(ctx, CompanionStyle.TILE_ICON)
                layoutParams = LinearLayout.LayoutParams(size, size).apply { bottomMargin = dp(ctx, 6) }
                background = box(ctx, PAPER, oval = true)
            })
            addView(text(ctx, label, CompanionStyle.TILE_TYPE).apply { gravity = Gravity.CENTER })
            clickable(this, onClick)
        }

    /** Header: title on the left, an optional small button on the right. */
    fun header(ctx: Context, title: String, action: String? = null, onAction: (() -> Unit)? = null): LinearLayout =
        HeaderBar(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(text(ctx, title, CompanionStyle.TITLE, bold = true), LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            if (action != null && onAction != null) {
                addView(
                    text(ctx, action, CompanionStyle.ACTION, bold = true).apply {
                        gravity = Gravity.CENTER
                        minHeight = dp(ctx, 56)
                        setPadding(dp(ctx, 16), 0, 0, 0)
                        clickable(this, onAction)
                    },
                    LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT),
                )
            }
            setPadding(0, dp(ctx, 8), 0, dp(ctx, 14))
        }

    /** A list row: label (+ small line) on the left, a value or control on the right, a thin rule below. */
    fun row(
        ctx: Context,
        label: CharSequence,
        sub: CharSequence? = null,
        right: View? = null,
        onClick: (() -> Unit)? = null,
        onLong: (() -> Unit)? = null,
        left: View? = null,
        /** A status line: approved launcher type, with natural wrapping and scrolling. */
        compact: Boolean = false,
    ): LinearLayout = RowLayout(ctx).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = dp(ctx, if (compact) INFO_ROW_DP else if (ctx is SettingsActivity) 112 else ROW_DP)
        val p = dp(ctx, if (compact) 4 else 6)
        setPadding(p, p, p, p)
        val rule = GradientDrawable().apply { setColor(PAPER) }
        val normal = android.graphics.drawable.LayerDrawable(arrayOf(box(ctx, LIGHT, strokeDp = 0, radiusDp = 0), rule)).apply {
            setLayerInset(1, 0, 0, 0, dp(ctx, 1))
        }
        val pressed = android.graphics.drawable.LayerDrawable(arrayOf(box(ctx, LIGHT, strokeDp = 0, radiusDp = 0), GradientDrawable().apply { setColor(PRESSED) })).apply {
            setLayerInset(1, 0, 0, 0, dp(ctx, 1))
        }
        background = if (onClick != null || onLong != null) pressable(normal, pressed) else normal
        if (left != null) addView(left)
        val col = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            tag = ROW_TEXT_TAG
            addView(text(ctx, label, if (compact) CompanionStyle.STATUS_TYPE else if (ctx is LocalReadingSettingsActivity) CompanionStyle.FORM_BODY else CompanionStyle.LABEL, bold = !compact))
            if (!sub.isNullOrEmpty()) addView(text(ctx, sub, if (compact) CompanionStyle.STATUS_CAPTION else if (ctx is LocalReadingSettingsActivity) CompanionStyle.FORM_CAPTION else CompanionStyle.BODY, color = MID))
        }
        addView(col, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        if (right != null) {
            control = right
            val lp = (right.layoutParams as? LinearLayout.LayoutParams)
                ?: LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            lp.marginStart = dp(ctx, ROW_GAP_DP)
            addView(right, lp)
        }
        clickable(this, onClick, onLong)
    }

    /** The tag on a row's text column (tests: the no-overlap rule). */
    const val ROW_TEXT_TAG = "row:text"

    fun value(ctx: Context, s: CharSequence, bold: Boolean = true, sp: Float = 20f): TextView =
        text(ctx, s, sp, bold = bold).apply { gravity = Gravity.END }

    /** On/Off control drawn as a box: filled when on. Changes instantly. */
    fun toggle(ctx: Context, on: Boolean): TextView = text(ctx, if (on) "On" else "Off", if (ctx is LauncherActivity) CompanionStyle.STATUS_CAPTION else CompanionStyle.CONTROL, bold = true, color = if (on) PAPER else INK).apply {
        gravity = Gravity.CENTER
        minWidth = dp(ctx, 76)
        minHeight = dp(ctx, 44)
        background = box(ctx, if (on) INK else PAPER, radiusDp = 22)
    }

    /** Checklist box: filled with a tick when done. */
    fun check(ctx: Context, done: Boolean): TextView = text(ctx, if (done) "✓" else "", 20f, bold = true, color = PAPER).apply {
        gravity = Gravity.CENTER
        val s = dp(ctx, 34)
        layoutParams = LinearLayout.LayoutParams(s, s).apply { marginEnd = dp(ctx, 14) }
        background = box(ctx, if (done) INK else PAPER, radiusDp = 2)
    }

    /** Letter in a circle, the mockup's app "icon". */
    fun letter(ctx: Context, label: String, sizeDp: Int = 44): TextView =
        text(ctx, label.firstOrNull { it.isLetterOrDigit() }?.uppercase(Locale.getDefault()) ?: "?", 20f, bold = true).apply {
            gravity = Gravity.CENTER
            val s = dp(ctx, sizeDp)
            layoutParams = LinearLayout.LayoutParams(s, s).apply { marginEnd = dp(ctx, 14) }
            background = box(ctx, PAPER, oval = true)
        }

    fun card(ctx: Context): LinearLayout = LinearLayout(ctx).apply {
        orientation = LinearLayout.VERTICAL
        background = box(ctx, PAPER)
        val p = dp(ctx, CompanionStyle.CARD_INSET)
        setPadding(p, p, p, p)
    }

    fun gap(ctx: Context, dpH: Int): View = View(ctx).apply {
        layoutParams = LinearLayout.LayoutParams(1, dp(ctx, dpH))
    }

    fun weightRow(ctx: Context, vararg views: View, gapDp: Int = 12): LinearLayout = LinearLayout(ctx).apply {
        orientation = LinearLayout.HORIZONTAL
        views.forEachIndexed { i, v ->
            addView(v, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                if (i > 0) marginStart = dp(ctx, gapDp)
            })
        }
    }

    fun clock(ctx: Context, wallMs: Long): String = DateFormat.getTimeFormat(ctx).format(Date(wallMs))

    /** A plain-words explanation with OK (Setup's Help). */
    fun note(a: android.app.Activity, text: String) {
        android.app.AlertDialog.Builder(a).setMessage(text).setPositiveButton("OK", null).show()
    }

    fun secs(ms: Long): String = String.format(Locale.US, "%.1f s", ms / 1000.0)
}
