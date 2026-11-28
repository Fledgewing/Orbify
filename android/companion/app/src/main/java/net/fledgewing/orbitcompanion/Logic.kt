package net.fledgewing.orbitcompanion

// Pure decisions with no Android imports, unit-tested in app/src/test.

enum class HomeAction { START_KOREADER, SHOW_LAUNCHER }

/**
 * What the HOME activity does. Times are a monotonic clock in ms (SystemClock.elapsedRealtime).
 *
 * - Every Home press starts KOReader with "home", except a second press within [doublePressMs],
 *   which shows the launcher page (and starts a new pair, so a third quick press goes back to
 *   KOReader).
 * - When Home comes back to the front without a press (the app on top closed, crashed or was
 *   killed), KOReader starts again, unless the last start was under [failWindowMs] ago: then
 *   KOReader is not staying up and the launcher page shows, so nobody is locked out.
 */
class HomeDecider(
    private val doublePressMs: Long = 2_000,
    private val failWindowMs: Long = 5_000,
) {
    private var lastPressAt: Long? = null
    private var lastStartAt: Long? = null

    /** [opensApp]: "Home opens" is KOReader or an app (false: the Orbit launcher page). */
    fun onHomePress(now: Long, koreaderInstalled: Boolean, opensApp: Boolean): HomeAction {
        val prev = lastPressAt
        lastPressAt = now
        if (!koreaderInstalled || !opensApp) return HomeAction.SHOW_LAUNCHER
        if (prev != null && now - prev in 0..doublePressMs) {
            lastPressAt = null
            return HomeAction.SHOW_LAUNCHER
        }
        lastStartAt = now
        return HomeAction.START_KOREADER
    }

    fun onUncovered(now: Long, koreaderInstalled: Boolean, opensApp: Boolean): HomeAction {
        if (!koreaderInstalled || !opensApp) return HomeAction.SHOW_LAUNCHER
        val last = lastStartAt
        if (last != null && now - last in 0 until failWindowMs) {
            lastStartAt = null
            return HomeAction.SHOW_LAUNCHER
        }
        lastStartAt = now
        return HomeAction.START_KOREADER
    }

    /** startActivity threw: forget the start so the crash window doesn't count it. */
    fun startFailed() {
        lastStartAt = null
    }

    /** KOReader started from the launcher page's button. */
    fun startedByHand(now: Long) {
        lastStartAt = now
    }
}

/** The "Wi-Fi after sleep sync" setting. */
enum class WifiAfterSleep(val key: String) {
    KEEP_ON("keep"),
    OFF_AFTER_30("off30"),
    OFF_NOW("now");

    companion object {
        val DEFAULT = OFF_AFTER_30
        fun fromKey(key: String?): WifiAfterSleep = entries.firstOrNull { it.key == key } ?: DEFAULT
    }
}

sealed class SleepWifiAction {
    object KeepOn : SleepWifiAction()
    object OffNow : SleepWifiAction()

    /** "Sync and sleep": NET_DONE comes before SLEEP_NOW, so the screen is still on. */
    object OffAtNextScreenOff : SleepWifiAction()
    data class OffAt(val deadlineMs: Long) : SleepWifiAction()
}

enum class TimerVerdict { TURN_OFF, SCREEN_ON, ALREADY_OFF, NOT_DUE, NO_TIMER }

object WifiPolicy {
    const val OFF_AFTER_MS = 30 * 60_000L
    const val SCREEN_OFF_GRACE_MS = 30_000L
    const val WAKE_LOCK_CAP_MS = 25_000L

    // An exact alarm can be delivered a little early or late; early by up to this still counts.
    private const val EARLY_SLACK_MS = 5_000L

    fun isSleepReason(reason: String?): Boolean = reason == "sleep" || reason == "sync_and_sleep"

    /**
     * What NET_DONE does with Wi-Fi. null: not a sleep sync, Wi-Fi is left alone.
     * [restoreOff]: Wi-Fi was off before this sleep sync (NET_DONE restore="off") and the user
     * didn't turn it on by hand, so it goes back off like "Off now".
     */
    fun afterSleepSync(mode: WifiAfterSleep, reason: String?, screenOn: Boolean, nowWallMs: Long, restoreOff: Boolean = false): SleepWifiAction? {
        if (!isSleepReason(reason)) return null
        return when (if (restoreOff) WifiAfterSleep.OFF_NOW else mode) {
            WifiAfterSleep.KEEP_ON -> SleepWifiAction.KeepOn
            // Scheduled even with the screen on: the timer checks the screen when it fires.
            WifiAfterSleep.OFF_AFTER_30 -> SleepWifiAction.OffAt(nowWallMs + OFF_AFTER_MS)
            WifiAfterSleep.OFF_NOW -> when {
                !screenOn -> SleepWifiAction.OffNow
                reason == "sync_and_sleep" -> SleepWifiAction.OffAtNextScreenOff
                else -> SleepWifiAction.KeepOn // woken again already: the reader is using it
            }
        }
    }

    /** The Wi-Fi-off timer fired. Wi-Fi goes off only if the screen is still off. */
    fun onTimer(nowWallMs: Long, deadlineMs: Long, screenOn: Boolean, wifiOn: Boolean): TimerVerdict = when {
        deadlineMs <= 0 -> TimerVerdict.NO_TIMER
        nowWallMs < deadlineMs - EARLY_SLACK_MS -> TimerVerdict.NOT_DUE
        !wifiOn -> TimerVerdict.ALREADY_OFF
        screenOn -> TimerVerdict.SCREEN_ON
        else -> TimerVerdict.TURN_OFF
    }

    /** NET_UP's wake_lock_s ("0" = none), hard-capped at 25 s. */
    fun wakeLockMs(raw: String?, enabled: Boolean): Long {
        if (!enabled) return 0
        val s = raw?.trim()?.toDoubleOrNull() ?: return 0
        if (s.isNaN() || s <= 0) return 0
        return minOf((s * 1000).toLong(), WAKE_LOCK_CAP_MS)
    }

    /** Whole minutes left, rounded up, for "Wi-Fi off in N min". */
    fun minutesLeft(nowWallMs: Long, deadlineMs: Long): Long {
        val left = deadlineMs - nowWallMs
        if (left <= 0) return 0
        return (left + 59_999) / 60_000
    }
}

/** At most one event per [intervalMs] (SLEEP_NOW). */
class RateLimiter(private val intervalMs: Long) {
    private var last: Long? = null

    fun tryAcquire(now: Long): Boolean {
        val l = last
        if (l != null && now - l in 0 until intervalMs) return false
        last = now
        return true
    }
}

/** A release version: MAJOR.MINOR.PATCH with an optional pre-release ("v" prefix and "+build" ignored). */
data class Version(val major: Int, val minor: Int, val patch: Int, val pre: String? = null) : Comparable<Version> {
    /** Monotonic Android versionCode, the same formula the release workflow uses. */
    val code: Int get() = AndroidVersionCode.encode(major, minor, patch, pre)

    /** Human label for the Updates screen; keep the wire version unchanged. */
    fun display(): String = "$major.$minor.$patch" + when {
        pre?.startsWith("preview.") == true -> " Preview ${pre.removePrefix("preview.")}"
        pre?.startsWith("rc.") == true -> " RC ${pre.removePrefix("rc.")}"
        pre != null -> "-$pre"
        else -> ""
    }

    override fun compareTo(other: Version): Int {
        compareValues(major, other.major).let { if (it != 0) return it }
        compareValues(minor, other.minor).let { if (it != 0) return it }
        compareValues(patch, other.patch).let { if (it != 0) return it }
        // A release sorts after any of its pre-releases (semver 11.3).
        if (pre == other.pre) return 0
        if (pre == null) return 1
        if (other.pre == null) return -1
        val a = pre.split('.')
        val b = other.pre.split('.')
        for (i in 0 until minOf(a.size, b.size)) {
            val x = a[i]
            val y = b[i]
            val xn = x.toLongOrNull()
            val yn = y.toLongOrNull()
            val c = when {
                xn != null && yn != null -> compareValues(xn, yn)
                xn != null -> -1 // numeric identifiers sort before alphanumeric ones
                yn != null -> 1
                else -> x.compareTo(y)
            }
            if (c != 0) return c
        }
        return compareValues(a.size, b.size)
    }

    override fun toString(): String = "$major.$minor.$patch" + (pre?.let { "-$it" } ?: "")

    companion object {
        private val RE = Regex("""^[vV]?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$""")

        fun parse(raw: String?): Version? {
            val m = RE.matchEntire(raw?.trim() ?: return null) ?: return null
            val (a, b, c, p) = m.destructured
            return Version(a.toIntOrNull() ?: return null, b.toIntOrNull() ?: return null, c.toIntOrNull() ?: return null, p.ifEmpty { null })
        }
    }
}

/** One GitHub release, reduced to what the updater needs. */
data class ReleaseInfo(val tag: String, val prerelease: Boolean, val draft: Boolean, val assets: Map<String, String>) {
    /** Null for a release that is not an Android one (firmware `xteink-v…`, anything else). */
    val version: Version? get() = ReleaseTags.version(tag)

    companion object {
        /** One object of GitHub's release JSON (org.json is pure Java, so this stays testable). */
        fun from(o: org.json.JSONObject): ReleaseInfo {
            val assets = LinkedHashMap<String, String>()
            val arr = o.optJSONArray("assets") ?: org.json.JSONArray()
            for (i in 0 until arr.length()) {
                val a = arr.getJSONObject(i)
                assets[a.getString("name")] = a.getString("browser_download_url")
            }
            return ReleaseInfo(o.optString("tag_name"), o.optBoolean("prerelease"), o.optBoolean("draft"), assets)
        }
    }
}

/**
 * BookSync releases both platforms from one repo (AGENTS.md "Releases"): Android tags are
 * `v<version>` (`android-v<version>` is read too), firmware tags `xteink-v<version>`, which the
 * Android pieces skip.
 */
object ReleaseTags {
    const val PREFIX = "android-v"

    /** Only GET /releases?per_page=N lists pre-releases; firmware releases share the list. */
    const val LIST_PAGE = 30

    fun version(tag: String): Version? {
        val t = tag.trim()
        return when {
            t.startsWith(PREFIX) -> Version.parse(t.removePrefix(PREFIX))
            t.startsWith("v") || t.startsWith("V") -> Version.parse(t)
            else -> null
        }
    }

    /** Tags to try for one version's release, the one in use first. */
    fun forVersion(v: String): List<String> = listOf("v$v", "$PREFIX$v")
}

/** BookSync's product version alone decides channel eligibility. */
enum class UpdateChannel(val key: String) {
    STABLE("stable"), RC("rc"), PREVIEW("preview");

    fun allows(version: Version?): Boolean {
        if (version == null) return false
        val pre = version.pre ?: return true
        return when {
            Regex("rc\\.[1-9][0-9]*").matches(pre) -> this != STABLE
            Regex("preview\\.[1-9][0-9]*").matches(pre) -> this == PREVIEW
            else -> false
        }
    }

    companion object {
        fun fromKey(key: String?) = values().firstOrNull { it.key == key } ?: STABLE
    }
}

object UpdatePolicy {
    const val INTERVAL_MS = 24 * 60 * 60_000L
    const val SUMS_NAME = "SHA256SUMS"

    fun apkName(v: Version) = "orbit-companion-$v.apk"

    /** At most one automatic check per 24 h; a clock that went backwards also allows one. */
    fun due(lastCheckMs: Long, nowMs: Long): Boolean = lastCheckMs <= 0 || nowMs < lastCheckMs || nowMs - lastCheckMs >= INTERVAL_MS

    /** The newest usable release allowed by the selected BookSync channel. */
    fun pick(releases: List<ReleaseInfo>, channel: UpdateChannel, withdrawn: Set<Version> = emptySet()): ReleaseInfo? =
        releases.filter { !it.draft && channel.allows(it.version) && it.version != null && !TestBuild.isTest(it.version) && it.version !in withdrawn }
            .maxWithOrNull(compareBy { it.version!! })

    fun shouldInstall(candidate: Version?, current: Version?, withdrawn: Set<Version>): Boolean =
        candidate != null && candidate !in withdrawn && candidate != current &&
            (isNewer(candidate, current) || current in withdrawn)

    fun isNewer(candidate: Version?, current: Version?): Boolean =
        candidate != null && (current == null || candidate > current)
}

/**
 * One app-update install session at a time (v0.11.2). On the M8C, with Play Protect's check held
 * up by a Play Store self-update, the second and third Install taps sat with no feedback, each
 * committing a new session, and were applied 30 s later; the first ended
 * INSTALL_FAILED_ABORTED. Pure: Updater keeps the state and asks PackageInstaller whether the
 * session still exists.
 */
object UpdateSession {
    enum class Phase { COMMITTED, PROMPTED, CHECKING }

    data class State(val id: Int, val version: String, val phase: Phase, val atMs: Long)

    /** A session with no result after this long is treated as gone. */
    const val STALE_MS = 10 * 60_000L
    const val CHECKING = "Android is checking the update…"
    const val CANCELLED = "Android cancelled the install; tap to try again"

    /** PackageInstaller.STATUS_FAILURE_ABORTED. */
    const val STATUS_ABORTED = 3

    /** A new session may be committed: none pending, or the pending one is gone or stale. */
    fun canCommit(s: State?, alive: Boolean, nowMs: Long): Boolean =
        s == null || !alive || nowMs - s.atMs >= STALE_MS || nowMs < s.atMs

    enum class Tap { NEW_CHECK, REOPEN_PROMPT, SAY_CHECKING }

    /** A tap on Check for updates: a new check, Android's prompt again, or "Android is checking". */
    fun onTap(s: State?, alive: Boolean, nowMs: Long): Tap = when {
        canCommit(s, alive, nowMs) -> Tap.NEW_CHECK
        s!!.phase == Phase.PROMPTED -> Tap.REOPEN_PROMPT
        else -> Tap.SAY_CHECKING
    }

    /** Back on our page from Android's prompt with the session still open: confirmed, Android checks. */
    fun afterPrompt(s: State?, alive: Boolean): State? =
        if (s != null && alive && s.phase == Phase.PROMPTED) s.copy(phase = Phase.CHECKING) else s

    /** The status line for a session that ended without installing. */
    fun failureLine(status: Int, message: String?, version: String): String =
        if (status == STATUS_ABORTED || message?.contains("INSTALL_FAILED_ABORTED") == true) CANCELLED
        else "v$version install failed ($status${if (message != null) ": $message" else ""})"
}

/**
 * A legacy artifact build (before preview versions, sideloaded by tools/sideload-android.sh):
 * `<next patch>-0.test.<run>`, e.g. 0.11.3-0.test.42 after v0.11.2. It is never published, so no
 * updater should offer it; and it sorts above the release it was built after but below every
 * release or pre-release of the next patch (a numeric "0" sorts before "rc", "beta", ...), so
 * the device leaves it for the next real release.
 */
object TestBuild {
    const val PRE_PREFIX = "0.test."

    fun isTest(v: Version?): Boolean = v?.pre?.startsWith(PRE_PREFIX) == true

    fun isTest(versionName: String?): Boolean = isTest(Version.parse(versionName))
}

/** `sha256sum` output: "<64 hex>  name" or "<64 hex> *name" per line. Bad lines are skipped. */
object Checksums {
    private val LINE = Regex("""^([0-9a-fA-F]{64}) [ *](.+)$""")

    fun parse(text: String): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        text.lineSequence().forEach { raw ->
            val m = LINE.matchEntire(raw.trimEnd('\r').trim()) ?: return@forEach
            out[m.groupValues[2].trim()] = m.groupValues[1].lowercase()
        }
        return out
    }
}

/** Whether another app can be used: missing, disabled ("frozen", e.g. by a vendor launcher) or fine. */
enum class AppState { MISSING, FROZEN, OK }

object AppStates {
    // PackageManager.COMPONENT_ENABLED_STATE_*
    private const val DISABLED = 2
    private const val DISABLED_USER = 3
    private const val DISABLED_UNTIL_USED = 4

    /**
     * [found]: the package exists (looked up with MATCH_DISABLED_COMPONENTS).
     * [enabledSetting]: getApplicationEnabledSetting. [appInfoEnabled]: ApplicationInfo.enabled.
     * [suspended]: ApplicationInfo.FLAG_SUSPENDED.
     */
    fun of(found: Boolean, enabledSetting: Int, appInfoEnabled: Boolean, suspended: Boolean): AppState = when {
        !found -> AppState.MISSING
        enabledSetting == DISABLED || enabledSetting == DISABLED_USER || enabledSetting == DISABLED_UNTIL_USED -> AppState.FROZEN
        !appInfoEnabled || suspended -> AppState.FROZEN
        else -> AppState.OK
    }

    /**
     * [disabler]: the label of the app that most likely disabled it (the vendor launcher, read at
     * run time), or null. [hint]: where that app re-enables it.
     */
    fun disabledMessage(app: String, disabler: String?, hint: String?): String = when {
        disabler != null && hint != null -> "$app is disabled by $disabler: re-enable it in $disabler › $hint."
        disabler != null -> "$app is disabled by $disabler: re-enable it there."
        else -> "$app is disabled by the system: re-enable it in Settings › Apps."
    }

    /** Short status value, e.g. "Disabled by Meebook Launcher". */
    fun disabledShort(disabler: String?): String = if (disabler != null) "Disabled by $disabler" else "Disabled by the system"
}

/**
 * The "Battery: Unrestricted (app)" setup row, read from the settings that can break the app
 * (AOSP android11-release):
 *
 * - Background restriction: the RUN_ANY_IN_BACKGROUND app-op (Settings'
 *   BackgroundActivityPreferenceController:119-127); for Orbit, ActivityManager.isBackgroundRestricted.
 * - Doze: only the deviceidle allowlist exempts an app (DeviceIdleController:2449-2453).
 *   isIgnoringBatteryOptimizations reads exactly that list (PowerManager:1803,
 *   PowerWhitelistManager:133-134).
 * - App Standby: the RARE and RESTRICTED buckets defer jobs and alarms (Orbit's own bucket only).
 *
 * An active device admin is NOT on the deviceidle list: DeviceIdleController has no admin rule, only
 * App Standby exempts it (AppStandbyController:1108-1109). Settings still shows such an app as
 * "Battery optimization not available" and "Background usage can't be restricted"
 * (SettingsLib PowerWhitelistBackend:79-81, 100-101), so Doze can defer it while Settings offers
 * no switch. That was Orbit on a Boox Page (v0.11.2): the row then says Settings can't change it
 * and names what can: Android's own "Allow" prompt (RequestIgnoreBatteryOptimizations:67-106,
 * which doesn't check for an admin), or `tools/install-usb.sh`, whose
 * `dumpsys deviceidle whitelist +pkg` is kept across reboots (DeviceIdleController:2261, saved to
 * deviceidle.xml, :1958, read back at boot, :3720). Met only once the allowlist says so.
 */
object BatteryRow {
    /** UsageStatsManager.STANDBY_BUCKET_RARE and STANDBY_BUCKET_RESTRICTED (API 30). */
    const val BUCKET_RARE = 40
    const val BUCKET_RESTRICTED = 45

    const val FIX = "set App battery usage › Unrestricted"
    const val LOCKED = "this reader won't let you change it in Settings: tap Open for Android's Allow prompt, or run tools/install-usb.sh over USB"
    const val LOCKED_OTHER = "this reader won't let you change it in Settings: run tools/install-usb.sh over USB"

    /** Where Open goes: Android's "Allow" prompt (Orbit only) or the app's battery page. */
    enum class Open { PROMPT, BATTERY_PAGE }

    data class Row(val done: Boolean, val detail: String, val open: Open = Open.BATTERY_PAGE)

    /**
     * [own]: the row is Orbit's. [backgroundRestricted]: RUN_ANY_IN_BACKGROUND denied, null when
     * Android won't say. [idleAllowlisted]: isIgnoringBatteryOptimizations. [standbyBucket]: Orbit's
     * bucket where readable, else null. [settingsLocked]: Settings shows the app as "not
     * available" (an active device admin), so its battery page has no switch to flip.
     */
    fun of(
        installed: Boolean,
        own: Boolean,
        backgroundRestricted: Boolean?,
        idleAllowlisted: Boolean,
        standbyBucket: Int?,
        settingsLocked: Boolean,
    ): Row = when {
        !installed -> Row(false, "not installed")
        backgroundRestricted == true -> Row(false, "background usage is restricted: $FIX")
        !idleAllowlisted && settingsLocked -> if (own) Row(false, LOCKED, Open.PROMPT) else Row(false, LOCKED_OTHER)
        !idleAllowlisted -> Row(false, FIX, if (own) Open.PROMPT else Open.BATTERY_PAGE)
        standbyBucket == BUCKET_RARE || standbyBucket == BUCKET_RESTRICTED ->
            Row(false, "Android is holding BookSync back (rarely used): open BookSync, then $FIX")
        else -> Row(true, "done")
    }
}

/** The shared "Wi-Fi" setting (android/docs/DESIGN.md "Wi-Fi modes"). The patch decides when; we switch. */
enum class WifiMode(val key: String, val label: String) {
    ALWAYS_ON("always_on", "Always on"),
    OFF_READING("off_reading", "Off while reading"),
    JIT("jit", "Just in time");

    companion object {
        val DEFAULT = JIT
        fun fromKey(key: String?): WifiMode = entries.firstOrNull { it.key == key } ?: DEFAULT
        fun valid(key: String?) = entries.any { it.key == key }
    }
}

/** The shared "Home button" setting. */
enum class HomeButton(val key: String, val label: String) {
    SMART("smart", "Back to my book, then library home"),
    LIBRARY(ServerAdapters.connector.homeModeKey, "library home");

    companion object {
        val DEFAULT = SMART
        fun fromKey(key: String?): HomeButton = entries.firstOrNull { it.key == key } ?: DEFAULT
        fun valid(key: String?) = entries.any { it.key == key }
    }
}

/**
 * "Sync while reading" (android/docs/INTERFACE.md "reading_schedule_request"). The patch owns it: it
 * reports its value in SETTINGS; a change here is a request (id, at ms) in /status that the
 * patch applies and saves at its next start, resume or menu open, then acknowledges
 * (reading_schedule_applied_at). Until then the companion shows the requested value.
 */
object ReadingSchedule {
    val OPTIONS = listOf(
        "off" to "Off",
        "min10" to "Every 10 minutes", "min15" to "Every 15 minutes", "min30" to "Every 30 minutes", "min60" to "Every 60 minutes",
        "pg25" to "Every 25 pages", "pg50" to "Every 50 pages", "pg100" to "Every 100 pages",
        "ch1" to "Every chapter", "ch2" to "Every 2 chapters",
    )

    fun valid(id: String?): Boolean = OPTIONS.any { it.first == id }

    fun label(id: String?): String = OPTIONS.firstOrNull { it.first == id }?.second ?: "Off"

    /** What the companion shows: a request not yet applied, else what the patch reported. */
    fun shown(patchValue: String, requestId: String): String =
        requestId.takeIf { valid(it) } ?: patchValue.takeIf { valid(it) } ?: "off"

    /** The patch reported [appliedAt]: our request is done when it covers [requestAt]. */
    fun requestDone(requestId: String, requestAt: Long, appliedAt: Long?): Boolean =
        requestId.isNotEmpty() && appliedAt != null && appliedAt >= requestAt

    /** /status field: the pending request, or null. */
    fun statusJson(requestId: String, requestAt: Long): String =
        if (valid(requestId) && requestAt > 0) "{\"id\":\"$requestId\",\"at\":$requestAt}" else "null"
}

object SharedSettings {
    val IDLE_MINUTES = listOf(1, 2, 5, 10)
    fun validIdle(v: Int?) = v != null && v in IDLE_MINUTES
}

/** Who turned Wi-Fi on. Only automatic (patch or companion) Wi-Fi is turned off automatically. */
enum class WifiOwner(val key: String) {
    NONE("none"), AUTO("auto"), MANUAL("manual");

    companion object {
        fun fromKey(key: String?): WifiOwner = entries.firstOrNull { it.key == key } ?: NONE
    }
}

object WifiOwnership {
    /** How long after our own setWifiEnabled(true) an ENABLED broadcast still counts as ours. */
    const val PENDING_MS = 60_000L

    /** Wi-Fi came on. Ours (with the owner we asked for) if we asked recently, else the user's. */
    fun onEnabled(nowMs: Long, pendingAtMs: Long, pendingOwner: WifiOwner?): WifiOwner =
        if (pendingOwner != null && pendingAtMs > 0 && nowMs - pendingAtMs in 0..PENDING_MS) pendingOwner else WifiOwner.MANUAL

    /** A WIFI_OFF: auto ones never turn off Wi-Fi the user turned on by hand. */
    fun allowOff(auto: Boolean, owner: WifiOwner): Boolean = !auto || owner != WifiOwner.MANUAL
}

/** Home press -> the COMMAND extra for KOReader (android/docs/INTERFACE.md "go home"). */
object HomeCommands {
    const val HOME = "home"
    const val HOME_SMART = "home_smart"
    const val FROM_OTHER_APP = "other_app"
    /** Save and quit, then the companion starts KOReader again (patch 0.3.1+, android/docs/INTERFACE.md). */
    const val RESTART = "restart"
    /** After a restart with a book open: reopen it at its place (patch 0.5.5+; older ones ignore it). */
    const val REOPEN_BOOK = "reopen_book"
    /** Setup's rows (plugin 0.11.0+): library's sign-in page, the recommended settings' review page. */
    const val SIGNIN = "signin"
    const val RECOMMENDED = "recommended"
    /** Settings' "Do now" buttons (docs/design/companion-settings.md A2, A4, A5); the work runs in KOReader. */
    const val FULL_REFRESH = "full_refresh"
    const val SYNC_SLEEP = "sync_sleep"
    const val TEST_SYNC_PATH = "test_sync_path"

    /** Every command the plugin obeys (shared/contract/companion.json koreader_start.commands). */
    val ALL = listOf(HOME, HOME_SMART, RESTART, REOPEN_BOOK, SIGNIN, RECOMMENDED, FULL_REFRESH, SYNC_SLEEP, TEST_SYNC_PATH)

    fun forPress(button: HomeButton): String = if (button == HomeButton.SMART) HOME_SMART else HOME

    /** Every HOME recovery carries navigation too; a plain start may reopen the last book. */
    fun forUncovered(button: HomeButton): String = forPress(button)

    /**
     * FROM extra. We only know for sure Home came from outside KOReader when one of our own pages
     * was in front, or KOReader had gone away (uncovered); otherwise the patch measures its pause.
     */
    fun from(companionPageInFront: Boolean, uncovered: Boolean): String? =
        if (companionPageInFront || uncovered) FROM_OTHER_APP else null
}

/**
 * The display's orientation for KOReader's Home (ROTATION extra, android/docs/INTERFACE.md "go
 * home"): how the device is held when Home is pressed. KOReader's file browser locks its own
 * rotation (fm_rotation_mode, else upright), which on Android turns the whole display; the
 * plugin turns library Home back to this one. [rotation] is Display.getRotation() (0-3, the
 * Surface.ROTATION_* quarter turns); [naturalPortrait]: the panel's natural (rotation 0)
 * orientation is portrait. Named as KOReader's rotation modes, the way KOReader's launcher reads
 * the display (android-luajit-launcher extensions/ActivityExtensions.kt:295-302,
 * getOrientationCompat: on a portrait panel ROTATION_90 is its reverse landscape).
 */
object HeldRotation {
    fun name(rotation: Int, naturalPortrait: Boolean): String? {
        val portrait = listOf("portrait", "reverse_landscape", "reverse_portrait", "landscape")
        val landscape = listOf("landscape", "portrait", "reverse_landscape", "reverse_portrait")
        return (if (naturalPortrait) portrait else landscape).getOrNull(rotation)
    }

    /** Sent with Home commands only: the plugin reads it with "home"/"home_smart". */
    fun sendsWith(command: String?): Boolean = command == HomeCommands.HOME || command == HomeCommands.HOME_SMART
}

/**
 * Which COMMAND each plugin version knows (android/docs/INTERFACE.md). The companion never sends
 * one the running plugin doesn't know (v0.11.1: with 0.10.1 running, Setup's Fix next sent
 * `signin` three times and `recommended` once; the plugin logged "unknown command ignored"):
 * KOReader then starts with no command. The running version is /status?patch_version=.
 */
object PluginCommands {
    /** command -> the first plugin version that obeys it. Absent: every plugin (home, home_smart). */
    val SINCE = mapOf(
        HomeCommands.RESTART to "0.3.1",
        HomeCommands.REOPEN_BOOK to "0.5.5",
        HomeCommands.SIGNIN to "0.11.0",
        HomeCommands.RECOMMENDED to "0.11.0",
        // The first plugin with them is the release after 0.11.2; its test builds are 0.11.3-0.test.N.
        HomeCommands.FULL_REFRESH to "0.11.3-0",
        HomeCommands.SYNC_SLEEP to "0.11.3-0",
        HomeCommands.TEST_SYNC_PATH to "0.11.3-0",
    )

    /** [running]: the plugin version KOReader runs (null: never reported; a versioned command then waits). */
    fun known(command: String?, running: String?): Boolean {
        val since = SINCE[command ?: return true] ?: return true
        val r = running?.let { Version.parse(it) } ?: return false
        return r >= Version.parse(since)!!
    }

    /** The command to send: [command] when the running plugin knows it, else none (null). */
    fun allowed(command: String?, running: String?): String? = if (known(command, running)) command else null

    /** The log line when a command is dropped. */
    fun droppedLine(command: String, running: String?) =
        "command=$command not sent: the running plugin (${running?.let { "v$it" } ?: "version unknown"}) doesn't know it (needs v${SINCE[command]}+)"
}

/**
 * A restart command must not be replaced by the next start's intent before KOReader reads it
 * (M8C v0.11.0: `command=restart` at 21:11:24.559, a Home press 0.9 s later sent `command=home`,
 * which replaced the intent; the restart was lost). For [WINDOW_MS] after a RESTART, while the
 * running plugin still reports the version it had then and no RELAUNCH came back, any other start
 * sends RESTART again. Pure; Koreader.start holds one.
 */
class RestartLatch {
    companion object {
        const val WINDOW_MS = 10_000L
    }

    private var sentAt = -1L
    private var sentRunning: String? = null

    /** A RESTART went out at [nowMs] (monotonic) while [running] ran. */
    fun sent(nowMs: Long, running: String?) {
        sentAt = nowMs
        sentRunning = running
    }

    /** KOReader read the restart (RELAUNCH came) or a new version runs: nothing to protect. */
    fun clear() {
        sentAt = -1L
        sentRunning = null
    }

    /** The command to send instead of [command]: RESTART while a restart may still be unread. */
    fun resolve(command: String?, nowMs: Long, running: String?): String? {
        if (command == HomeCommands.RESTART || sentAt < 0) return command
        if (nowMs - sentAt !in 0..WINDOW_MS || running != sentRunning) {
            clear()
            return command
        }
        return HomeCommands.RESTART
    }
}

/** Setup's Wi-Fi off/on test leaves Wi-Fi as it found it. */
object WifiTestPlan {
    enum class Step { OFF, ON }

    /** Was on: off, then on (times the reconnect). Was off: on (timed), then back off. */
    fun steps(wasOn: Boolean): List<Step> = if (wasOn) listOf(Step.OFF, Step.ON) else listOf(Step.ON, Step.OFF)
}

/** Plain-English network errors for update checks. */
object NetErrors {
    const val BLOCKED = "Internet blocked: is 'Block connections without VPN' on for Tailscale?"
    const val NO_ANSWER = "GitHub didn't answer (the network may still be starting). Try again in a minute."

    /** Waits before the 2nd and 3rd try after a connect timeout or reset; each try connects within 8 s. */
    val RETRY_WAITS_MS = listOf(3_000L, 10_000L)
    const val CONNECT_TIMEOUT_MS = 8_000

    /** A connect timeout or reset: often gone seconds after Wi-Fi or Tailscale comes up. */
    fun transient(e: Throwable): Boolean {
        var t: Throwable? = e
        while (t != null) {
            if (t is java.net.SocketTimeoutException) return true
            if (t is java.net.SocketException && t.message.orEmpty().contains("reset", ignoreCase = true)) return true
            t = t.cause
        }
        return false
    }

    /** Runs [block], retrying transient failures after each of [waits] (ms). */
    fun <T> withRetry(waits: List<Long> = RETRY_WAITS_MS, sleep: (Long) -> Unit, note: (Int, Exception, Long) -> Unit = { _, _, _ -> }, block: () -> T): T {
        var i = 0
        while (true) {
            try {
                return block()
            } catch (e: Exception) {
                if (i >= waits.size || !transient(e)) throw e
                note(i + 1, e, waits[i])
                sleep(waits[i])
                i++
            }
        }
    }
    const val LOCKDOWN_WARNING =
        "Block connections without VPN is on: internet (updates) is blocked. VPN settings › Tailscale ⚙ › turn it off"

    /** always_on_vpn_lockdown: "1" on, "0" off, anything else unknown. */
    fun lockdown(value: String?): Boolean? = when (value?.trim()) {
        "1" -> true
        "0" -> false
        else -> null
    }

    /**
     * [kind]: "permission" (EACCES/EPERM), "connect" (no route, refused, timeout, DNS) or other.
     */
    /** [lockdown]: "Block connections without VPN" as read; only true blames it. */
    fun message(kind: String, wifiEnabled: Boolean, wifiConnected: Boolean, lockdown: Boolean?, detail: String): String = when {
        kind == "permission" && lockdown == true -> BLOCKED
        kind == "permission" -> "no internet: Android refused the connection ($detail)"
        kind == "connect" && !wifiEnabled -> "no internet: Wi-Fi is off"
        kind == "connect" && !wifiConnected -> "no internet: Wi-Fi isn't connected"
        kind == "connect" && lockdown == true -> BLOCKED
        kind == "connect" -> NO_ANSWER
        else -> "check failed: $detail"
    }

    /** EACCES/EPERM: what Android returns when lockdown blocks a socket outside the VPN. */
    fun kindOf(e: Throwable): String {
        var t: Throwable? = e
        while (t != null) {
            val m = t.message.orEmpty()
            if (m.contains("EACCES") || m.contains("EPERM") || m.contains("Permission denied", ignoreCase = true) ||
                t is SecurityException
            ) {
                return "permission"
            }
            t = t.cause
        }
        return if (e is java.net.UnknownHostException || e is java.net.ConnectException ||
            e is java.net.SocketTimeoutException || e is java.net.NoRouteToHostException
        ) {
            "connect"
        } else {
            "other"
        }
    }
}

/**
 * The Setup row "Orbit plugin installed" (the KOReader plugin the companion installs): the file decides "outdated"; the version the
 * running patch reports (broadcasts, /status ping) decides "restart to finish".
 */
enum class PatchRowState { MISSING, OUTDATED, RESTART, CURRENT }

object PatchRow {
    /** The first patch that obeys COMMAND=restart (android/docs/INTERFACE.md). */
    const val RESTART_COMMAND_SINCE = "0.3.1"

    /** file: PATCH_VERSION on disk (the plugin, else the old patch; null: missing or unreadable). running: last reported. */
    fun state(file: String?, running: String?, app: String): PatchRowState {
        if (file == null && running == null) return PatchRowState.MISSING
        val have = file ?: running
        if (PatchFile.needsInstall(have, app)) return PatchRowState.OUTDATED
        val f = file?.let { Version.parse(it) } ?: return PatchRowState.CURRENT
        val r = running?.let { Version.parse(it) } ?: return PatchRowState.CURRENT
        return if (r < f) PatchRowState.RESTART else PatchRowState.CURRENT
    }

    /** The running patch can restart KOReader on the companion's command. */
    fun canRestart(running: String?): Boolean {
        val r = running?.let { Version.parse(it) } ?: return false
        return r >= Version.parse(RESTART_COMMAND_SINCE)!!
    }
}

/**
 * One update covers everything (android/docs/DESIGN.md "One update"): after the companion updates,
 * its new process installs the release's patch, and the running patch (0.5.0+, RestartPlan)
 * loads it by a restart that never interrupts reading. One status line says how it went.
 */
object UpdateFlow {
    /** The first patch that restarts KOReader by itself for a newer file on disk. */
    const val AUTO_RESTART_SINCE = "0.5.0"

    /**
     * Install the release's patch after an app update: only over an older installed file
     * (never a downgrade of a newer patch-only update; a first install is Setup's step).
     */
    fun patchAfterUpdate(file: String?, app: String): Boolean =
        file != null && Version.parse(app) != null && PatchFile.needsInstall(file, app)

    /** The running patch loads a newer file by itself. */
    fun autoRestart(running: String?): Boolean {
        val r = running?.let { Version.parse(it) } ?: return false
        return r >= Version.parse(AUTO_RESTART_SINCE)!!
    }

    /** The running patch reports [awaiting] (or newer): the restart happened. */
    fun loaded(awaiting: String, running: String?): Boolean {
        val w = Version.parse(awaiting) ?: return false
        val r = running?.let { Version.parse(it) } ?: return false
        return r >= w
    }

    fun doneLine(app: String) = "Updated to v$app (KOReader loaded it)"

    /**
     * The patch is installed. [now]: the user started the update, KOReader restarts at once;
     * otherwise at the next screen-off (or the plugin's own save-and-quit in the background).
     */
    fun installedLine(app: String, now: Boolean = false) =
        if (now) "Updated to v$app; KOReader restarts now to load it (an open book reopens)"
        else "Updated to v$app; KOReader loads it the next time it starts"

    enum class Restart { NOW, WAIT, NONE }

    /**
     * When the companion may restart KOReader (v0.11.1, user decision): a MANUAL update (the user
     * tapped Update or Install) restarts at once, book open or not: the plugin saves the book and
     * reopens it, and returns to library Home if that was on top. An automatic update never
     * restarts KOReader from the companion while the screen is on, not even with no book open or
     * on library Home: only at [screenOff] (the plugin also saves and quits by itself when
     * KOReader goes to the background).
     */
    fun mayRestart(manual: Boolean, screenOff: Boolean): Restart = if (manual || screenOff) Restart.NOW else Restart.WAIT

    /**
     * The companion's side of the restart after a patch install (v0.5.2): COMMAND=restart, which
     * every patch since 0.3.1 obeys. [awaiting]: the installed version not yet running (""/null:
     * none); [sentFor]: the version a restart was already sent for (once per version, no loop);
     * [manual]: the user started this update; [screenOff]: the trigger is the screen going off.
     */
    fun restart(awaiting: String?, running: String?, sentFor: String?, manual: Boolean, screenOff: Boolean = false): Restart = when {
        awaiting.isNullOrEmpty() || loaded(awaiting, running) -> Restart.NONE
        sentFor == awaiting -> Restart.NONE
        else -> mayRestart(manual, screenOff)
    }

    /**
     * KOReader runs an older patch than the file on disk, however the file got there (v0.5.4:
     * M8C 11-22 ran 0.4.6 with 0.5.3 installed, by an earlier companion, so no restart was
     * pending). One per (running, file) pair per process: [StaleRestart] keeps the pairs.
     * Same rule as [restart]: at once when [manual], else only at [screenOff].
     */
    fun staleRestart(running: String?, file: String?, manual: Boolean, screenOff: Boolean, sent: Set<String>): Restart {
        val r = running?.let { Version.parse(it) } ?: return Restart.NONE
        val f = file?.let { Version.parse(it) } ?: return Restart.NONE
        if (f <= r || pairKey(running, file) in sent) return Restart.NONE
        return mayRestart(manual, screenOff)
    }

    fun pairKey(running: String, file: String) = "$running>$file"

    /** How long a user-started update counts as one across the app replace (v0.5.5). */
    const val USER_UPDATE_MS = 30 * 60_000L

    /**
     * The update in progress was started by the user (a check by hand, the update notification's
     * tap, Setup's Install patch): "update" means restart KOReader now, book or not; the patch
     * saves the book and it reopens at the same place. [atMs]: when they started it (0: never).
     */
    fun userStarted(nowMs: Long, atMs: Long): Boolean = atMs > 0 && nowMs - atMs in 0..USER_UPDATE_MS

    /**
     * The patch install that follows a change of this app's version restarts KOReader now (v0.6.1).
     * At targetSdk 28 every app update waits for the user's tap on Android's install prompt
     * (a background check only posts a notification), so every app replace was user-confirmed,
     * with no mark needed: the old process (0.5.4 and earlier) never wrote one (M8C 11-22 02:06).
     * Only a patch-only update goes by [userStarted]'s mark.
     */
    fun restartNowAfter(appReplaced: Boolean, nowMs: Long, markAtMs: Long): Boolean =
        appReplaced || userStarted(nowMs, markAtMs)

    /** The relaunch after a restart: reopen the book that was open (patch 0.5.5+ obeys it). */
    fun relaunchCommand(bookWasOpen: Boolean): String? = if (bookWasOpen) HomeCommands.REOPEN_BOOK else null

    fun staleLine(running: String, file: String) = "restart: KOReader runs $running, file has $file"

    /**
     * KOReader's book state from a STATS broadcast: reason "suspend" always says open=0 (not being
     * read), so it doesn't count; null means no change.
     */
    fun bookFromStats(reason: String?, open: String?): Boolean? = when {
        reason == "suspend" -> null
        open == "1" -> true
        open == "0" -> false
        else -> null
    }

    /** The manual fallback, with the reason. */
    fun manualLine(app: String, reason: String) =
        "Updated to v$app, but the KOReader patch wasn't updated: $reason. Setup > BookSync plugin"
}

/** The pairs a stale-patch restart was sent (or a wait logged) for, in this process. */
class StaleRestart {
    private val sent = mutableSetOf<String>()
    private val waited = mutableSetOf<String>()

    /** The decision; NOW is recorded so the same pair never restarts again (no loop). [log] gets a line once per pair and outcome. */
    fun decide(running: String?, file: String?, manual: Boolean, screenOff: Boolean, log: (String) -> Unit = {}): UpdateFlow.Restart {
        val d = UpdateFlow.staleRestart(running, file, manual, screenOff, sent)
        if (d == UpdateFlow.Restart.NONE || running == null || file == null) return d
        val key = UpdateFlow.pairKey(running, file)
        if (d == UpdateFlow.Restart.NOW) {
            sent += key
            log(UpdateFlow.staleLine(running, file))
        } else if (waited.add(key)) {
            log(UpdateFlow.staleLine(running, file) + "; KOReader loads it at its next start (the plugin quits it in the background) or restarts at the next screen-off")
        }
        return d
    }
}

/**
 * Setup holds its prompts while an update settles (v0.5.5; M8C 11-22 01:42 prompted for the
 * patch and the clicker mid-update): for [GRACE_MS] after the version changed, and while the
 * patch install and restart that follow it run. Meanwhile the patch row is pending, and the
 * clicker (accessibility) row is pending until its service reconnects after the package
 * replace, or the grace ends (also after any process start). Only what is still wrong after
 * that prompts.
 */
object AfterUpdate {
    const val GRACE_MS = 30_000L

    /** [justUpdated]: the version changed and Setup hasn't seen it yet; [patchBusy]: install or restart running. */
    fun settling(nowMs: Long, updatedAtMs: Long, justUpdated: Boolean, patchBusy: Boolean): Boolean =
        justUpdated || patchBusy || (updatedAtMs > 0 && nowMs - updatedAtMs in 0 until GRACE_MS)

    /** Rows that count as pending (never needed, never a regression) right now. */
    fun pendingRows(settling: Boolean, processAgeMs: Long, clickerConnected: Boolean): Set<String> {
        val out = mutableSetOf<String>()
        if (settling) out += "patch"
        if (!clickerConnected && (settling || processAgeMs in 0 until GRACE_MS)) out += "clicker"
        return out
    }
}

/**
 * The Orbit KOReader plugin (android/koreader/orbit.koplugin): released as [ZIP], installed as
 * koreader/plugins/[PLUGIN]; its main.lua declares PATCH_VERSION. Up to 0.7.x it was the user
 * patch koreader/patches/[OLD_PATCH], which the install deletes (docs/design/orbit-plugin.md).
 */
object PatchFile {
    const val ZIP = "orbit.koplugin.zip"
    const val PLUGIN = "orbit.koplugin"
    const val OLD_PATCH = "2-orbit-android.lua"
    private val VERSION = Regex("""(?m)^local PATCH_VERSION = "([^"]+)"""")

    /**
     * A zip entry's path inside the plugin folder, or null when it is outside "orbit.koplugin/"
     * or could escape it (absolute, "..", ".", backslashes, empty parts). Folder entries end in "/".
     */
    fun zipMember(name: String): String? {
        val rel = name.removePrefix("$PLUGIN/").takeIf { it != name && it.isNotEmpty() } ?: return null
        if ('\\' in rel) return null
        val parts = rel.removeSuffix("/").split('/')
        return if (parts.any { it.isEmpty() || it == "." || it == ".." }) null else rel
    }

    /** PATCH_VERSION declared in the file's text, or null. */
    fun version(text: String?): String? = text?.let { VERSION.find(it)?.groupValues?.get(1) }

    /** Install or update when missing, unreadable or older than the app's release. */
    fun needsInstall(installed: String?, app: String): Boolean {
        val a = Version.parse(app) ?: return installed == null
        val i = installed?.let { Version.parse(it) } ?: return true
        return i < a
    }
}

/**
 * "Setup needs you": which Setup rows to prompt about (android/docs/DESIGN.md "Setup needs you").
 * Rows are identified by a stable id (idOf). A prompt shows for rows that aren't done and
 * aren't ignored, unless snoozed with "Later". A snooze lasts until the next app update or
 * until a row regresses (done, then not done again).
 */
object SetupAttention {
    /** Rows that report a test or a sighting, not a setting: never prompted about. */
    val INFO_ONLY = setOf("patch_seen", "wifi_test", "keymapper", "play_protect", "managed", "freeze_tip")

    fun idOf(label: String): String = ServerAdapters.connector.setupId(label) ?: when {
        label.startsWith("Set BookSync as Home") -> "home"
        label.startsWith("Allow notifications") -> "notifications"
        label.startsWith("Not disabled") -> "disabled"
        label.startsWith("Install updates") -> "install_updates"
        label.startsWith("Battery:") -> "battery:" + label.substringAfter("(", "").substringBefore(")")
        label.startsWith("Tailscale") -> "tailscale"
        label.startsWith("Allow \"lock screen\"") -> "admin"
        // "KOReader patch …" up to 0.7.x: kept so earlier snoozes and ignores still apply.
        label.startsWith("BookSync plugin installed") || label.startsWith("KOReader patch installed") -> "patch"
        label.startsWith("KOReader app") -> "koreader"
        label.startsWith("library plugin") -> "plugin"
        label.startsWith("Play Protect") -> "play_protect"
        label.startsWith("Launcher can freeze apps") -> "freeze_tip"
        label.startsWith("Family Link") || label.startsWith("Managed device") -> "managed"
        label.startsWith("BookSync plugin answered") || label.startsWith("KOReader patch answered") -> "patch_seen"
        label.startsWith("Wi-Fi off/on test") -> "wifi_test"
        label.startsWith("Clicker buttons") -> "clicker"
        label.startsWith("Signed in to library") -> "signed_in"
        label.startsWith("Recommended settings") -> "recommended"
        label.startsWith("BookSync keyboard") -> "keyboard"
        label.startsWith("Key Mapper") || label.startsWith("Another key mapper") -> "keymapper"
        else -> label.lowercase().replace(Regex("[^a-z0-9]+"), "_").trim('_')
    }

    data class State(
        val ignored: Set<String> = emptySet(),
        val snoozeCode: Int = 0,
        val snoozeNotDone: Set<String> = emptySet(),
        val lastDone: Set<String> = emptySet(),
    )

    /** needed: rows to fix (not done, not ignored); regressed: of those, done last time; show: prompt now. */
    data class Result(val needed: List<String>, val regressed: Set<String>, val show: Boolean, val next: State, val pending: List<String> = emptyList())

    /** After an in-app fix finishes: close the prompt ("All set") when nothing is left to show. */
    fun allSet(r: Result): Boolean = r.needed.isEmpty() && r.pending.isEmpty()

    /**
     * [pending]: rows that are fine but wait on something outside the app (e.g. "Restart
     * KOReader to finish"): counted as done, never a "needs you", but listed in an open prompt.
     */
    fun evaluate(rows: List<Pair<String, Boolean>>, st: State, versionCode: Int, pending: Set<String> = emptySet()): Result {
        val done = rows.filter { it.second || it.first in pending }.map { it.first }.toSet()
        val needed = rows.filter { it.first !in done && it.first !in INFO_ONLY && it.first !in st.ignored }.map { it.first }
        val waiting = rows.map { it.first }.filter { it in pending && it !in st.ignored }
        val regressed = needed.filter { it in st.lastDone }.toSet()
        // A row fixed since the snooze leaves it; if it breaks again it is new to the snooze.
        val snoozeLeft = st.snoozeNotDone - done
        val snoozed = st.snoozeCode == versionCode && snoozeLeft.containsAll(needed)
        val next = st.copy(snoozeNotDone = snoozeLeft, lastDone = done)
        return Result(needed, regressed, needed.isNotEmpty() && !snoozed, next, waiting)
    }

    /** "Later": quiet until the next update or a regression. */
    fun snooze(st: State, needed: List<String>, versionCode: Int): State =
        st.copy(snoozeCode = versionCode, snoozeNotDone = needed.toSet())

    /**
     * "Prompt at the moment of cause": rows a change in the companion just made needed (not
     * needed before it). Shown at once, snooze or not: the user is right here.
     */
    fun caused(before: Collection<String>, after: Result): List<String> = after.needed.filter { it !in before }

    /**
     * Home press: show the prompt once before KOReader when an unsnoozed row is new since the
     * last Home prompt ([prompted]: the rows it showed).
     */
    fun homePrompt(r: Result, prompted: Set<String>): Boolean = r.show && !prompted.containsAll(r.needed)

    /** The rows an unsnoozed prompt is about ("" when none): KOReader shows its box once per key. */
    fun promptKey(r: Result): String = if (r.show) r.needed.sorted().joinToString(",") else ""

    fun ignore(st: State, id: String): State = st.copy(ignored = st.ignored + id)
    fun unignoreAll(st: State): State = st.copy(ignored = emptySet())
}

/** User-visible changes per version, shown once after an update ("What's new"). */
object WhatsNew {
    val NOTES: List<Pair<String, List<String>>> = listOf(
        "0.2.2" to listOf(
            "Home goes book → library home → this launcher → back to your book.",
            "Setup can install the KOReader patch for you.",
            "A setup guide for new readers: android/docs/SETUP.md.",
        ),
        "0.2.3" to listOf("No more \"Connecting to Wi-Fi\" message when the reader wakes."),
        "0.2.4" to listOf(
            "Setup now tells you when a step needs you (here, in a quiet notification, and in KOReader's BookSync status).",
            "This list: what changed after each update.",
        ),
        "0.3.0" to listOf(
            "Battery: hours left, % per hour in standby and reading, by setting and content, and a daily history (BookSync Companion › Battery).",
            "Export a battery summary and compare readers side by side.",
        ),
        "0.3.1" to listOf(
            "Setup: after installing the KOReader patch, the step updates at once; if KOReader still runs the old patch, a \"Restart KOReader\" button finishes it.",
        ),
        "0.3.2" to listOf(
            "Settings › Home opens: KOReader + library, or any reader app (Readest, Moon+ Reader, …). Home brings it back where it was; press Home twice for the launcher page.",
        ),
        "0.4.0" to listOf(
            "Settings › Clicker buttons: map a Bluetooth clicker's buttons (press, hold, double press) to next/previous page, Home, Back, frontlight or Sync and sleep.",
            "In KOReader pages turn exactly; in other apps it taps the page once you switch on Settings › Accessibility › BookSync clicker buttons.",
            "Using Key Mapper for this? Turn it off once BookSync's buttons work; you can then uninstall it.",
        ),
        "0.4.1" to listOf(
            "Clicker buttons: a default action per button, and any app can use its own (e.g. Next page, but Volume down in Readest).",
            "New actions: Send Volume up/down and Send key (Page up/down, arrows, Space), through the BookSync keyboard. It switches in only for the key press, then your keyboard comes back.",
            "Setup steps show up when they appear: right after you map a clicker, on the next Home press, and once in KOReader outside a book.",
        ),
        "0.4.2" to listOf(
            "Clicker buttons work in KOReader again, including keyboard-mode and gamepad clickers.",
            "With Settings › Accessibility › BookSync clicker buttons on, one path handles every app: in KOReader it tells the patch, which turns the page exactly. Media keys now work in KOReader this way too.",
        ),
        "0.4.3" to listOf(
            "KOReader no longer freezes (\"not responding\") while the patch checks for an update: the check runs in the background, never with a book open, and waits an hour after a failure.",
        ),
        "0.4.4" to listOf(
            "Settings PIN (optional): Settings › Settings PIN locks the settings, Setup fixes, updates, Android Settings and any app you add, and KOReader's BookSync menu. Forgot it? See the setup guide.",
            "Clicker buttons now sits right under the Home button in Settings.",
        ),
        "0.4.5" to listOf(
            "Update checks retry twice when GitHub doesn't answer right after Wi-Fi comes up, and no longer blame 'Block connections without VPN' unless it is on.",
        ),
        "0.4.6" to listOf(
            "Settings PIN: works as soon as it's set, unlocks only while you stay in the settings or the app you unlocked, and on Boox guards only the Settings screen (no longer the launcher). Home on KOReader's file browser opens library home again.",
        ),
        "0.4.7" to listOf(
            "Home opens library home again on KOReader 2025.10 and newer (KOReader now wraps the plugin's actions, which the patch took as missing). Test sync path and Apply recommended settings work there too.",
        ),
        "0.4.8" to listOf(
            "Settings PIN: after you leave the settings or a guarded app it stays unlocked for 2 minutes, so coming straight back needs no PIN. The screen turning off still locks it.",
            "Sync while reading is now in Settings too (KOReader keeps it; a change applies when KOReader opens).",
            "Home settings are simpler: \"Home opens\" now offers the BookSync launcher page (it replaces the \"Home always opens…\" switch), and \"In KOReader, Home goes to\" shows only with KOReader.",
        ),
        "0.4.9" to listOf(
            "Home on any library screen other than its main page (a book, a list, search, a sheet) goes back to library's main page; Home on the main page opens the launcher page.",
        ),
        "0.5.0" to listOf(
            "One update covers everything: after the app updates it installs the matching KOReader patch itself, and KOReader restarts to load it once no book is open (or when the device next sleeps). It never interrupts reading.",
            "The Settings PIN keypad no longer covers an install: the installer, permission screens and Play Protect's scan pass while an update runs and for a minute after, even with the Play Store guarded.",
        ),
        "0.5.1" to listOf(
            "Setup installs the rest: one tap each for the official KOReader, the library plugin and the KOReader patch, every download checked. A new reader needs only this app sideloaded.",
            "Setup › Fix next walks every open step in order and comes back after each one. Setup also explains up front what may get in the way: Play Protect's warnings, a launcher that freezes apps, Family Link.",
        ),
        "0.5.2" to listOf(
            "After an update, KOReader restarts by itself to load the new patch, whichever patch it ran before; with a book open it waits until you close it. No Setup step, and no Settings PIN for update steps.",
            "No more \"setup step needs you\" for a step already being done, and What's new is a line on this page instead of a notification.",
            "Pages keep their scroll position when they update (Check for updates, Fix, toggles).",
            "Apply recommended settings in KOReader sets library's \"Make library home\" only where the plugin knows that setting.",
        ),
        "0.5.3" to listOf(
            "Setup's tips (Family Link, Play Protect, a launcher that freezes apps) have \"Got it\" and never count as steps; \"Show hidden tips\" brings them back.",
            "With a Settings PIN, a guarded app that pops up by itself while you read (such as the Play Store) is sent back instead of showing the keypad. The keypad shows when you open the app.",
        ),
        "0.5.4" to listOf(
            "KOReader restarts to load a newer patch whenever it runs an older one, however the patch got there (after your book, if one is open).",
            "Home on library's second page (or any list past its first page) goes to page 1 first; Home on page 1 goes to the launcher.",
        ),
        "0.5.5" to listOf(
            "An update you start yourself restarts KOReader right away, and your book reopens where you were. Background updates still wait for the book.",
            "No Setup prompt in the middle of an update.",
            "Every companion page scrolls.",
        ),
        "0.6.0" to listOf(
            "In library, any library, collection or list can be shown by series or by author: Sort › By series / By author.",
        ),
        "0.6.1" to listOf(
            "After any app update, KOReader restarts right away and your book reopens where you were.",
        ),
        "0.6.2" to listOf(
            "With a Settings PIN, a Boox library (and any launcher app) never asks for the PIN; only its settings screens do. Guarded apps lists every guarded entry so each can be turned off.",
        ),
        "0.7.0" to listOf(
            "Orbify: the app and the KOReader patch now update from github.com/Fledgewing/Orbify, one home for Android and Xteink readers. Nothing changes on the reader.",
        ),
        "0.11.0" to listOf(
            "Recommended settings are applied by themselves in KOReader: only settings still at their default change, anything you set yourself is listed for review, and Undo puts back what was there. Setup shows them, and whether KOReader is signed in to library.",
        ),
    )

    /** Notes for versions newer than [fromCode] up to [toCode] (Version.code), oldest first. */
    /** The status page's line ("What's new in v0.5.2 ›"), or null. */
    fun line(pending: Boolean, version: String): String? = if (pending) "What's new in v$version ›" else null

    fun since(fromCode: Int, toCode: Int, notes: List<Pair<String, List<String>>> = NOTES): List<Pair<String, List<String>>> =
        notes.filter { (v, _) ->
            val version = Version.parse(v) ?: return@filter false
            val from = NewIn.versionOf(fromCode)
            val to = NewIn.versionOf(toCode) ?: return@filter false
            (from == null || version > from) && version <= to
        }
}

/**
 * "Home opens" (android/docs/DESIGN.md): KOReader + library (the default, "") or any launchable app,
 * by package. For another app a Home press just brings it to the front; the KOReader commands
 * (home / home_smart) and the patch's Smart Home steps don't apply.
 */
object HomeApp {
    const val KOREADER_LIBRARY = ""
    const val KOREADER_PKG = "org.koreader.launcher"
    /** "Orbit launcher page": Home shows the companion's launcher page (was the toggle's off). */
    const val LAUNCHER = "orbit:launcher"

    fun isKoreader(choice: String?): Boolean = choice.isNullOrEmpty() || choice == KOREADER_PKG

    fun isLauncher(choice: String?): Boolean = choice == LAUNCHER

    /** Another app (its package). */
    fun isApp(choice: String?): Boolean = !isKoreader(choice) && !isLauncher(choice)

    /** "koreader", "launcher" or "app": /status settings.home_opens for the patch. */
    fun kind(choice: String?): String = when {
        isKoreader(choice) -> "koreader"
        isLauncher(choice) -> "launcher"
        else -> "app"
    }

    /**
     * 0.4.7 and older: "Home opens" plus the toggle "Home always opens …" (home_opens_koreader;
     * off = the launcher page). [toggle] null = never set (on).
     */
    fun migrate(choice: String, toggle: Boolean?): String = if (toggle == false) LAUNCHER else choice

    const val LAUNCHER_LABEL = "BookSync launcher page"
    const val TWICE = "press Home twice for the launcher page"
    const val HOME_BUTTON_TITLE = "In KOReader, Home goes to"

    /** Settings' "Home opens" row: what it opens, and the double press unless that is the launcher. */
    fun summary(choice: String?, appLabel: String?): String = when {
        isLauncher(choice) -> LAUNCHER_LABEL
        isKoreader(choice) -> "KOReader + library · $TWICE"
        else -> "${appLabel ?: choice} · $TWICE"
    }

    /** The "Home button" choice applies (and shows) only with KOReader + library. */
    fun showsHomeButton(choice: String?): Boolean = isKoreader(choice)

    /** pkg null = KOReader (with command/from); else that app, no extras. */
    data class Launch(val pkg: String?, val command: String?, val from: String?)

    fun launch(choice: String?, press: Boolean, button: HomeButton, companionPageInFront: Boolean): Launch {
        if (!isKoreader(choice)) return Launch(choice, null, null) // the launcher page never gets here (HomeDecider)
        val command = if (press) HomeCommands.forPress(button) else HomeCommands.forUncovered(button)
        val from = if (command == HomeCommands.HOME_SMART) HomeCommands.from(companionPageInFront, !press) else null
        return Launch(null, command, from)
    }

    /** The picker: known reader apps first, then everything else; A–Z within each. KOReader is the default row, not listed. */
    fun order(apps: List<Pair<String, String>>, readers: Set<String>): List<Pair<String, String>> =
        apps.filter { it.first != KOREADER_PKG }.distinctBy { it.first }
            .sortedWith(compareBy<Pair<String, String>>({ it.first !in readers }, { it.second.lowercase() }))
}
