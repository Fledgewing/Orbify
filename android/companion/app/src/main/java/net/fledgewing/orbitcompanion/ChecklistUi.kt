package net.fledgewing.orbitcompanion

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import net.fledgewing.orbitcompanion.Checklist.State

/**
 * Draws the Setup checklist (docs/design/companion-checklist.md) from a Checklist.Page: the same
 * rows on the Setup page, the "Setup needs you" prompt and the status page's card (D18).
 * E-ink (§3.10): no animation, no timed redraw; every state is a glyph and words.
 */
object ChecklistUi {
    /** What the page's taps do (SetupActivity). */
    interface Actions {
        fun verb(i: Checklist.Item)
        fun tap(i: Checklist.Item)
        fun summaryButton()
        fun group(key: String)
        fun gotIt(tipId: String)
        fun showHiddenTips()
        fun details()
        fun mode()
    }

    data class Tip(val id: String, val label: String, val detail: String)

    /** The parts around the rows: tips, Details' line, the mode line, which group is open. */
    data class Frame(
        val tips: List<Tip> = emptyList(),
        val managed: String? = null,
        val hiddenTips: Int = 0,
        val detailsLine: String = "",
        val modeLine: String = "",
        val open: String? = null,
    )

    const val TIPS = "tips"
    private const val VERB_DP = 56

    /** The state's box (§3.4): filled ✓, thick empty, dashed –, thin …; [mark] numbers a first-run step. */
    fun glyph(ctx: Context, state: State, mark: String? = null): TextView {
        val done = state == State.DONE || state == State.SET_BY_READER
        val t = when (state) {
            State.DONE, State.SET_BY_READER -> "✓"
            State.NEEDS_YOU -> mark ?: ""
            State.OFF -> "–"
            State.CHECKING -> "…"
        }
        return Ui.text(ctx, t, 18f, bold = true, color = if (done) Ui.PAPER else Ui.INK).apply {
            gravity = Gravity.CENTER
            val s = Ui.dp(ctx, 35)
            layoutParams = LinearLayout.LayoutParams(s, s).apply { marginEnd = Ui.dp(ctx, 12) }
            background = GradientDrawable().apply {
                cornerRadius = Ui.dp(ctx, 3).toFloat()
                setColor(if (done) Ui.INK else Ui.PAPER)
                when (state) {
                    State.NEEDS_YOU -> setStroke(Ui.dp(ctx, 3), Ui.INK)
                    State.OFF -> setStroke(Ui.dp(ctx, 2), Ui.INK, Ui.dp(ctx, 4).toFloat(), Ui.dp(ctx, 3).toFloat())
                    State.CHECKING -> setStroke(Ui.dp(ctx, 1), Ui.INK)
                    else -> Unit
                }
            }
        }
    }

    private fun SpannableStringBuilder.bold(s: String, color: Int = Ui.INK): SpannableStringBuilder {
        val start = length
        append(s)
        setSpan(StyleSpan(Typeface.BOLD), start, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        setSpan(ForegroundColorSpan(color), start, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        return this
    }

    /** "Until then: …" with its first words bold in ink. */
    private fun SpannableStringBuilder.loss(line: String): SpannableStringBuilder {
        val colon = line.indexOf(':')
        return if (colon < 0) append(line) else bold(line.substring(0, colon + 1)).append(line.substring(colon + 1))
    }

    fun label(i: Checklist.Item): CharSequence {
        val b = SpannableStringBuilder().bold(i.row.label)
        i.newIn?.let { tag ->
            b.append("  ")
            val start = b.length
            b.append("[${tag.uppercase()}]")
            b.setSpan(RelativeSizeSpan(0.7f), start, b.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            b.setSpan(StyleSpan(Typeface.BOLD), start, b.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        return b
    }

    /** The lines under a row's label: state, an extra line, the loss line. */
    fun sub(i: Checklist.Item): CharSequence {
        val b = SpannableStringBuilder()
        val r = i.row
        val stateLine = when {
            i.skipped -> "Skipped"
            i.state == State.SET_BY_READER -> "Set by the reader ⓘ"
            // An optional row that is off shows its own hint (what to do), if it has one.
            r.optional -> if (i.state == State.OFF) r.stateLine else ""
            else -> r.stateLine
        }
        if (i.regressed) b.bold("Stopped working: ")
        b.append(stateLine)
        if (r.optional && i.state != State.OFF && r.stateLine.isNotEmpty()) b.loss(r.stateLine)
        r.extra?.let { if (b.isNotEmpty()) b.append("\n"); b.bold(it) }
        i.loss?.let { if (b.isNotEmpty()) b.append("\n"); b.loss(it) }
        return b
    }

    /** One row (the same on the page, the prompt and the battery detail). */
    fun itemRow(ctx: Context, i: Checklist.Item, locked: Boolean, onVerb: (() -> Unit)?, onTap: (() -> Unit)?, mark: String? = null): LinearLayout {
        val verb = if (Checklist.verbShown(i, locked) && onVerb != null) {
            Ui.button(ctx, i.row.verb!!, heightDp = VERB_DP, sp = CompanionStyle.ACTION) { onVerb() }
        } else null
        return Ui.row(ctx, label(i), sub(i), verb, onClick = if (locked && !i.row.pinFree) null else onTap, left = glyph(ctx, i.state, mark))
    }

    fun section(ctx: Context, title: String): TextView =
        Ui.text(ctx, title.uppercase(), 15f, bold = true).apply {
            letterSpacing = 0.06f
            setPadding(0, Ui.dp(ctx, 12), 0, Ui.dp(ctx, 2))
        }

    /** The summary card: 2 dp black border, glyph and title, a line, the full-width button. */
    fun summaryCard(ctx: Context, s: Checklist.Summary, line: String = Checklist.summaryLine(s), onButton: (() -> Unit)?): LinearLayout =
        LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            background = Ui.box(ctx, Ui.PAPER, strokeDp = 2, radiusDp = CompanionStyle.CARD_RADIUS)
            val p = Ui.dp(ctx, 16)
            setPadding(p, p, p, p)
            val title = LinearLayout(ctx).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                if (s !is Checklist.Summary.FirstRun && s !is Checklist.Summary.Walking) addView(glyph(ctx, Checklist.summaryState(s)))
                addView(Ui.text(ctx, Checklist.summaryTitle(s), CompanionStyle.SUMMARY_TYPE, bold = true))
            }
            addView(title)
            addView(Ui.text(ctx, line, CompanionStyle.BODY, color = Ui.MID).apply { setPadding(0, Ui.dp(ctx, 2), 0, 0) })
            val b = Checklist.summaryButton(s)
            if (b != null && onButton != null) {
                addView(Ui.gap(ctx, 8))
                addView(Ui.button(ctx, b, solid = s !is Checklist.Summary.Walking, heightDp = CompanionStyle.FORM_TARGET, sp = CompanionStyle.FORM_ACTION) { onButton() },
                    LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
            }
            if (onButton != null && b == null) Ui.clickable(this, onButton)
        }

    private fun groupTitle(g: Checklist.GroupView): CharSequence {
        val b = SpannableStringBuilder().bold(g.group.title)
        if (g.newTag) {
            val start = b.length
            b.append("  [NEW]")
            b.setSpan(RelativeSizeSpan(0.7f), start, b.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        return b
    }

    /** The whole page below the header (§3.1). */
    fun render(ctx: Context, root: LinearLayout, page: Checklist.Page, frame: Frame, act: Actions) {
        root.addView(summaryCard(ctx, page.summary, onButton = if (Checklist.summaryButton(page.summary) != null) act::summaryButton else null))
        // D16: Managed explains other failures, so it stays visible under the summary.
        frame.managed?.let { m ->
            root.addView(Ui.gap(ctx, 8))
            root.addView(Ui.card(ctx).apply { addView(Ui.text(ctx, m, 16f)) })
        }
        if (page.needs.isNotEmpty()) {
            root.addView(section(ctx, when {
                page.locked -> "Needs a grown-up"
                page.numbered -> "Steps"
                else -> "Needs you"
            }))
            page.needs.forEachIndexed { n, i ->
                root.addView(itemRow(ctx, i, page.locked, { act.verb(i) }, { act.tap(i) }, mark = if (page.numbered) "${n + 1}" else null))
            }
        }
        if (page.ready.isNotEmpty()) {
            root.addView(section(ctx, "Ready now"))
            page.ready.forEach { i -> root.addView(itemRow(ctx, i, page.locked, { act.verb(i) }, { act.tap(i) })) }
        }
        root.addView(Ui.gap(ctx, 4))
        page.groups.forEach { g ->
            val key = g.group.name
            val open = frame.open == key
            root.addView(Ui.row(ctx, groupTitle(g), if (open && g.group != Checklist.Group.OPTIONAL) null else g.line.ifEmpty { null },
                Ui.value(ctx, if (open) "⌄" else "›"), onClick = { act.group(key) }, left = glyph(ctx, g.state)))
            if (open) {
                val inner = indent(ctx)
                g.items.forEach { i -> inner.addView(itemRow(ctx, i, page.locked, { act.verb(i) }, { act.tap(i) })) }
                root.addView(inner)
            }
        }
        if (frame.tips.isNotEmpty() || (frame.hiddenTips > 0 && !page.locked)) {
            val open = frame.open == TIPS
            val n = frame.tips.size
            root.addView(Ui.row(ctx, SpannableStringBuilder().bold("Tips"), "$n tip${if (n == 1) "" else "s"}${if (frame.hiddenTips > 0) " · ${frame.hiddenTips} hidden" else ""}",
                Ui.value(ctx, if (open) "⌄" else "›"), onClick = { act.group(TIPS) }, left = plain(ctx, "i")))
            if (open) {
                val inner = indent(ctx)
                frame.tips.forEach { t ->
                    inner.addView(Ui.row(ctx, t.label, t.detail, if (page.locked) null else Ui.button(ctx, "Got it", heightDp = VERB_DP, sp = 18f) { act.gotIt(t.id) }))
                }
                if (frame.hiddenTips > 0 && !page.locked) inner.addView(Ui.row(ctx, "Show hidden tips (${frame.hiddenTips})", onClick = { act.showHiddenTips() }))
                root.addView(inner)
            }
        }
        root.addView(Ui.row(ctx, SpannableStringBuilder().bold("Details"), frame.detailsLine.ifEmpty { null }, Ui.value(ctx, "›"),
            onClick = { act.details() }, left = plain(ctx, "≡")))
        if (frame.modeLine.isNotEmpty()) {
            root.addView(Ui.text(ctx, frame.modeLine, 16f, color = Ui.MID).apply {
                setPadding(0, Ui.dp(ctx, 8), 0, 0)
                if (!page.locked) Ui.clickable(this, act::mode)
            })
        }
    }

    private fun indent(ctx: Context) = LinearLayout(ctx).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(Ui.dp(ctx, 14), 0, 0, 0)
        background = android.graphics.drawable.LayerDrawable(arrayOf(Ui.box(ctx, Ui.INK, strokeDp = 0, radiusDp = 0), GradientDrawable().apply { setColor(Ui.PAPER) })).apply {
            setLayerInset(1, Ui.dp(ctx, 2), 0, 0, 0)
        }
    }

    private fun plain(ctx: Context, s: String): TextView = Ui.text(ctx, s, 18f, bold = true).apply {
        gravity = Gravity.CENTER
        val d = Ui.dp(ctx, 35)
        layoutParams = LinearLayout.LayoutParams(d, d).apply { marginEnd = Ui.dp(ctx, 12) }
    }

    /** The status page's card (§3.8): "Setup: all set ✓" or what needs the user. */
    fun statusCard(ctx: Context, s: Checklist.Summary, items: List<Checklist.Item>, onClick: () -> Unit): View =
        LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            background = Ui.pressable(Ui.box(ctx, Ui.PAPER, strokeDp = 2, radiusDp = CompanionStyle.CARD_RADIUS), Ui.box(ctx, Ui.PRESSED, strokeDp = 2, radiusDp = CompanionStyle.CARD_RADIUS))
            val p = Ui.dp(ctx, 12)
            setPadding(p, p, p, p)
            minimumHeight = Ui.dp(ctx, Ui.ROW_DP)
            addView(LinearLayout(ctx).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(glyph(ctx, Checklist.summaryState(s)))
                addView(Ui.text(ctx, Checklist.statusTitle(s), 21f, bold = true))
            })
            addView(Ui.text(ctx, Checklist.statusLine(s, items), 16f, color = Ui.MID))
            Ui.clickable(this, onClick)
        }
}

/** Battery detail (§3.5, mockup 7): one line per installed app with its own state and verb. */
class SetupBatteryActivity : EinkActivity() {
    override fun onResume() {
        super.onResume()
        render()
    }

    private fun render() {
        val root = page(scroll = true)
        root.addView(Ui.header(this, "Battery", "‹ Setup") { finish() })
        root.addView(Ui.text(this, "Android pauses restricted apps while the screen is off. These need to keep running, so sleep syncs and Wi-Fi switching happen on time.", 17f)
            .apply { setPadding(0, 0, 0, Ui.dp(this@SetupBatteryActivity, 8)) })
        val locked = Pin.locked(this)
        val checks = Setup.checks(this).filter { it.battery != null }
        val ignored = Prefs(this).setupIgnored
        var firstSet: String? = null
        checks.forEach { c ->
            val app = c.battery!!
            val st = BatteryMerge.state(app)
            val state = when (st) {
                BatteryMerge.AppState.DONE -> State.DONE
                BatteryMerge.AppState.SET_BY_READER -> State.SET_BY_READER
                else -> if (app.id in ignored) State.OFF else State.NEEDS_YOU
            }
            val row = Checklist.Row(app.id, app.name, st == BatteryMerge.AppState.DONE || st == BatteryMerge.AppState.SET_BY_READER,
                BatteryMerge.appLine(app), verb = BatteryMerge.appVerb(app))
            val item = Checklist.Item(row, state, Checklist.Group.PERMISSIONS, skipped = state == State.OFF, regressed = false, newIn = null)
            if (st == BatteryMerge.AppState.NEEDS_YOU && firstSet == null) firstSet = app.name
            root.addView(ChecklistUi.itemRow(this, item, locked, onVerb = {
                // Help: what can change it where Settings can't (BatteryRow: the USB command).
                if (BatteryMerge.appVerb(app) == "Help") Ui.note(this, "${app.name}: ${app.row.detail}") else c.run(this)
            }, onTap = {
                if (st == BatteryMerge.AppState.SET_BY_READER) Ui.note(this, SET_BY_READER_NOTE.format(app.name))
            }))
        }
        firstSet?.let { name ->
            root.addView(Ui.gap(this, 12))
            root.addView(Ui.card(this).apply {
                addView(Ui.text(this@SetupBatteryActivity, "Set opens $name's battery page. Choose Unrestricted, then press Back to return here.", 17f))
            })
        }
    }

    companion object {
        /** The ⓘ note (§3.4): the words never name a cause. */
        const val SET_BY_READER_NOTE = "This reader's own battery settings already keep %s running, and they can't be changed here. There's nothing to do.\n\nIf this reader ever does start pausing it, this row will say so and show what to do."
    }
}

/** Details (§3.6): what a support conversation needs, and Copy for support. Nothing here is counted. */
class SetupDetailsActivity : EinkActivity() {
    private var generation = 0
    override fun onResume() {
        super.onResume()
        load()
    }
    private fun load(showLoading: Boolean = true) {
        val ticket = ++generation
        if (showLoading) render(null)
        LibraryDiagnostics.snapshot(this) { snapshot ->
            if (ticket == generation && !isFinishing && !isDestroyed) render(snapshot)
        }
    }
    override fun onPause() {
        generation++
        super.onPause()
    }

    private fun render(crashes: LibraryDiagnostics.Snapshot?) {
        val root = page(scroll = true)
        root.addView(Ui.header(this, "Details", "‹ Setup") { finish() })
        val lines = crashes?.setup.orEmpty()
        lines.forEach { (k, v) -> root.addView(Ui.row(this, k, v)) }
        root.addView(Ui.gap(this, 20))
        root.addView(Ui.text(this, "Companion crashes", CompanionStyle.FORM_HEADING, bold = true).apply { typeface = CompanionStyle.serif })
        root.addView(Ui.gap(this, 14))
        root.addView(Ui.text(this, crashes?.text ?: "Loading crash summaries…", CompanionStyle.FORM_BODY))
        if (!Pin.locked(this)) {
            if (crashes?.canClear == true) root.addView(Ui.button(this, "Clear crash summaries", heightDp = CompanionStyle.FORM_TARGET, sp = CompanionStyle.FORM_ACTION, radiusDp = CompanionStyle.FORM_RADIUS) {
                val ticket = ++generation
                LibraryDiagnostics.clear(this) { ok ->
                    if (ticket == generation && !isFinishing && !isDestroyed) {
                        if (ok) load(false) else render(crashes.copy(text = "Crash summary unavailable", canClear = true))
                    }
                }
            })
            if (crashes != null) {
                root.addView(Ui.gap(this, 12))
                root.addView(Ui.button(this, "Copy for support", heightDp = CompanionStyle.FORM_TARGET, sp = CompanionStyle.FORM_ACTION, radiusDp = CompanionStyle.FORM_RADIUS) {
                    val text = SetupDetails.copyText(BuildConfig.VERSION_NAME, lines + ("Companion crashes" to crashes.text))
                    (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("BookSync setup details", text))
                    OLog.i("setup: details copied for support")
                    Ui.note(this, "Copied. Paste it into your message.")
                })
            }
        }
    }

    companion object {
        fun open(ctx: Context) = ctx.startActivity(Intent(ctx, SetupDetailsActivity::class.java))
    }
}
