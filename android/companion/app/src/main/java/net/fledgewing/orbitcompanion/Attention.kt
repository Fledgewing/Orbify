package net.fledgewing.orbitcompanion

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.LinearLayout

/**
 * "Setup needs you" (SetupAttention): evaluated when the service starts, after an update and
 * when the status page or launcher page opens. Delivered as a prompt page (AttentionActivity),
 * a quiet notification, a one-line launcher banner, and setup_needed in /status for the patch.
 */
object Attention {
    // "setup" was IMPORTANCE_LOW: hidden from the status bar and easy to miss on e-ink. A
    // channel's importance can't be raised once created, so it is replaced.
    private const val OLD_CHANNEL = "setup"
    private const val CHANNEL = "setup_steps"
    private const val ID = 4

    private fun state(p: Prefs) = SetupAttention.State(p.setupIgnored, p.setupSnoozeCode, p.setupSnoozeNotDone, p.setupLastDone)
    private fun save(p: Prefs, st: SetupAttention.State) {
        p.setupIgnored = st.ignored
        p.setupSnoozeCode = st.snoozeCode
        p.setupSnoozeNotDone = st.snoozeNotDone
        p.setupLastDone = st.lastDone
    }

    /** After an update, remember where "What's new" starts. A fresh install shows none. */
    fun onStart(ctx: Context) {
        val p = Prefs(ctx)
        val now = BuildConfig.VERSION_CODE
        val last = p.lastSeenVersionCode
        if (last in 1 until now) {
            p.whatsNewFromCode = last
            p.updatedFromCode = last
            p.appUpdatedAt = System.currentTimeMillis()
            OLog.i("setup: updated from code $last to $now; what's new pending; prompts held ${AfterUpdate.GRACE_MS / 1000} s")
            // What is still wrong once the update settled prompts then.
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(
                { evaluate(ctx.applicationContext, "after the update settled") }, AfterUpdate.GRACE_MS + 2_000,
            )
        }
        if (last != now) p.lastSeenVersionCode = now
    }

    class Eval(val result: SetupAttention.Result, val checks: Map<String, Check>)

    fun evaluate(ctx: Context, why: String, notify: Boolean = true): Eval {
        val p = Prefs(ctx)
        // A patch install or restart in progress isn't a step for the user.
        val checks = Setup.checks(ctx).associateBy { it.id }
            .let { all -> if (PatchInstaller.inProgress(ctx)) all - "patch" else all }
        // An update settling: the patch and a reconnecting clicker wait, and nothing prompts.
        val settling = AfterUpdate.settling(
            System.currentTimeMillis(), p.appUpdatedAt, p.lastSeenVersionCode != BuildConfig.VERSION_CODE,
            PatchInstaller.afterUpdateBusy || PatchInstaller.busy || PatchInstaller.inProgress(ctx),
        )
        val processAge = android.os.SystemClock.elapsedRealtime() - android.os.Process.getStartElapsedRealtime()
        val held = AfterUpdate.pendingRows(settling, processAge, ClickerService.connected)
        val pending = checks.filterValues { it.pending }.keys + held.filter { it in checks }
        // Add-on: only the four required rows and recommended-settings conflicts remind (§4.4).
        val rows = AddonLogic.attentionRows(p.mode, checks.filterValues { !it.optional }.map { (id, c) -> id to c.done })
        val raw = SetupAttention.evaluate(rows, state(p), BuildConfig.VERSION_CODE, pending)
        val r = if (settling) raw.copy(show = false) else raw
        save(p, r.next)
        p.setupNeeded = r.needed.size
        p.setupPromptKey = SetupAttention.promptKey(r)
        p.setupPromptRows = if (r.show) r.needed.mapNotNull { checks[it]?.label }.joinToString("\n") else ""
        if (r.needed.isNotEmpty() || r.regressed.isNotEmpty()) {
            OLog.i("setup: $why: needs ${r.needed}${if (r.regressed.isNotEmpty()) " (regressed ${r.regressed})" else ""}, prompt ${r.show}${if (settling) " (update settling: held)" else ""}")
        }
        if (notify && !settling) notification(ctx, r)
        StatusFile.write(ctx, why)
        return Eval(r, checks)
    }

    /** The rows that need the user now (for "before" in [afterChange]). */
    fun neededNow(ctx: Context): List<String> = evaluate(ctx, "before a change", notify = false).result.needed

    /**
     * "Prompt at the moment of cause": a change made in the companion (e.g. the first mapped
     * clicker button, a Send-key action) made new rows needed: open the prompt at once.
     */
    fun afterChange(a: Activity, before: List<String>, why: String): Boolean {
        val e = evaluate(a, why)
        val caused = SetupAttention.caused(before, e.result)
        if (caused.isEmpty()) return false
        OLog.i("setup: $why made $caused needed: prompting now")
        a.startActivity(Intent(a, AttentionActivity::class.java).putExtra(AttentionActivity.EXTRA_FIRST, caused.toTypedArray()))
        return true
    }

    /** KOReader's setup box "Later" (SETUP_LATER): the same snooze as the prompt's Later. */
    fun laterFromKoreader(ctx: Context) {
        val e = evaluate(ctx, "koreader later", notify = false)
        if (e.result.needed.isNotEmpty()) later(ctx, e) else OLog.i("setup: Later from KOReader; nothing needed")
    }

    fun whatsNew(ctx: Context): List<Pair<String, List<String>>> {
        val from = Prefs(ctx).whatsNewFromCode
        return if (from > 0) WhatsNew.since(from, BuildConfig.VERSION_CODE) else emptyList()
    }

    /** What's new is a line on the status page, never a prompt or notification by itself. */
    fun shouldPrompt(e: Eval, @Suppress("UNUSED_PARAMETER") ctx: Context) = e.result.show

    fun later(ctx: Context, e: Eval) {
        val p = Prefs(ctx)
        save(p, SetupAttention.snooze(state(p), e.result.needed, BuildConfig.VERSION_CODE))
        p.whatsNewFromCode = 0
        p.setupPromptKey = ""
        p.setupPromptRows = ""
        OLog.i("setup: Later (snoozed ${e.result.needed} until an update or a regression)")
        cancel(ctx)
    }

    fun ignore(ctx: Context, id: String) {
        val p = Prefs(ctx)
        save(p, SetupAttention.ignore(state(p), id))
        OLog.i("setup: don't ask about $id")
    }

    fun unignoreAll(ctx: Context) {
        val p = Prefs(ctx)
        save(p, SetupAttention.unignoreAll(state(p)))
        OLog.i("setup: asking about every row again")
    }

    fun seenWhatsNew(ctx: Context) {
        Prefs(ctx).whatsNewFromCode = 0
    }

    private fun nm(ctx: Context) = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun cancel(ctx: Context) {
        Reading.drop(Reading.KEY_SETUP)
        nm(ctx).cancel(ID)
    }

    private var lastNoteLog: String? = null

    /**
     * At most one notification: only for steps that truly need the user. Never while reading
     * (Reading): held, then evaluated again at the next moment nobody reads, so a step fixed
     * meanwhile posts nothing.
     */
    private fun notification(ctx: Context, r: SetupAttention.Result) {
        if (!r.show || r.needed.isEmpty()) return cancel(ctx)
        val app = ctx.applicationContext
        var immediate = true
        // Posted now runs inside show(); held, it runs later and looks again at what is still needed.
        Reading.show(app, Reading.KEY_SETUP, "setup reminder") {
            post(app, if (immediate) r else evaluate(app, "after reading", notify = false).result)
        }
        immediate = false
    }

    private fun post(ctx: Context, r: SetupAttention.Result) {
        if (!r.show || r.needed.isEmpty()) return cancel(ctx)
        val nm = nm(ctx)
        if (nm.getNotificationChannel(OLD_CHANNEL) != null) nm.deleteNotificationChannel(OLD_CHANNEL)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Setup steps", NotificationManager.IMPORTANCE_DEFAULT).apply {
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        })
        val n = r.needed.size
        val text = "BookSync Companion: $n setup step${if (n == 1) "" else "s"} need${if (n == 1) "s" else ""} you"
        val open = Intent(ctx, AttentionActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        nm.notify(ID, Notification.Builder(ctx, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat)
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
            .setContentIntent(PendingIntent.getActivity(ctx, 4, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            .build())
        // Vendor ROMs may block or demote it: log what Android says, once per change.
        val importance = nm.getNotificationChannel(CHANNEL)?.importance
        val line = "setup: notification posted ($text); notifications ${if (nm.areNotificationsEnabled()) "allowed" else "BLOCKED"}, channel importance $importance"
        if (line != lastNoteLog) OLog.i(line)
        lastNoteLog = line
    }
}

/** The prompt: what's new after an update, then only the rows that need the user. */
class AttentionActivity : EinkActivity() {
    companion object {
        /** Rows a change just made needed: listed first. */
        const val EXTRA_FIRST = "first"
    }

    private var eval: Attention.Eval? = null
    /** Something was fixed from inside this page: when nothing is left, say "All set" before closing. */
    private var fixedHere = false

    override fun onResume() {
        super.onResume()
        render()
    }

    /** An in-app fix finished (e.g. the patch install): look again. */
    override fun refresh() {
        if (!isFinishing) render()
    }

    private fun render() {
        val e = Attention.evaluate(this, "prompt page")
        eval = e
        val news = Attention.whatsNew(this)
        val needed = e.result.needed
        val pending = e.result.pending
        if (news.isEmpty() && (needed.isEmpty() && (pending.isEmpty() || !fixedHere))) {
            if (fixedHere) {
                val root = page()
                root.addView(Ui.header(this, "All set"))
                root.addView(Ui.text(this, "Every setup step is done.", 20f))
                root.postDelayed({ finish() }, 1_500)
            } else {
                finish()
            }
            return
        }
        val root = page(scroll = true)
        val title = if (needed.isNotEmpty() || pending.isNotEmpty()) "Setup needs you" else "What's new"
        root.addView(Ui.header(this, title, "Close") { closeOut() })
        news.forEach { (v, lines) ->
            root.addView(Ui.text(this, "New in $v", 20f, bold = true).apply { setPadding(0, Ui.dp(this@AttentionActivity, 8), 0, Ui.dp(this@AttentionActivity, 4)) })
            lines.forEach { root.addView(Ui.text(this, "• $it", 18f)) }
        }
        if (needed.isNotEmpty() || pending.isNotEmpty()) {
            val first = intent.getStringArrayExtra(EXTRA_FIRST).orEmpty().toList()
            // The same rows as Setup's Needs you (companion-checklist D18): words, loss lines, verbs.
            val checks = Setup.checks(this)
            // Verbs stay: each goes through Pin.fix, which asks for the PIN first (Check.run).
            val locked = false
            val items = Setup.items(this, checks).filter { i -> i.row.ids.any { it in needed || it in pending } }
            val rank = { i: Checklist.Item -> i.row.ids.minOf { id -> (first.indexOf(id).takeIf { it >= 0 } ?: (first.size + needed.indexOf(id).let { if (it < 0) needed.size else it })) } }
            items.sortedBy(rank).forEach { i ->
                val ids = i.row.ids.filter { it in needed }
                // "Installing…" while the patch install runs: no second install.
                val busy = PatchInstaller.busy && i.id == "patch"
                val shown = if (ids.any { it in e.result.regressed }) i.copy(regressed = true) else i
                val state = if (ids.isNotEmpty()) shown.copy(state = Checklist.State.NEEDS_YOU) else shown
                root.addView(ChecklistUi.itemRow(this, state, locked, onVerb = {
                    if (busy) return@itemRow
                    fixedHere = true
                    if (i.id == "battery" && i.row.verb == "Help") startActivity(Intent(this, SetupBatteryActivity::class.java))
                    else Setup.checkFor(i, checks)?.run(this)
                    render()
                }, onTap = null))
                if (ids.isNotEmpty()) {
                    root.addView(Ui.button(this, "Don't ask about this", heightDp = 56, sp = 16f) {
                        ids.forEach { Attention.ignore(this, it) }
                        render()
                    })
                }
                root.addView(Ui.gap(this, 8))
            }
            if (needed.isNotEmpty()) {
                root.addView(Ui.button(this, "Later") {
                    Attention.later(this, e)
                    finish()
                })
                root.addView(Ui.text(this, "Later: not again until the next update or until a step stops working. A step you skip stays in Setup, where Allow asks about it again.", 15f, color = Ui.MID))
            } else {
                root.addView(Ui.button(this, "OK") { closeOut() })
            }
        } else {
            root.addView(Ui.gap(this, 12))
            root.addView(Ui.button(this, "OK") { closeOut() })
        }
    }

    private fun closeOut() {
        Attention.seenWhatsNew(this)
        eval?.let { if (it.result.needed.isNotEmpty()) Attention.later(this, it) }
        finish()
    }
}
