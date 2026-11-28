package net.fledgewing.orbitcompanion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeDeciderTest {
    private val start = HomeAction.START_KOREADER
    private val launcher = HomeAction.SHOW_LAUNCHER

    @Test fun manualSyncDoesNotSelectAfterSleepWifiPolicy() {
        assertNull(WifiPolicy.afterSleepSync(WifiAfterSleep.OFF_NOW, "menu_sync", true, 0, restoreOff = true))
        assertFalse(WifiPolicy.isSleepReason("menu_sync"))
    }

    @Test
    fun singlePressesStartKoreader() {
        val d = HomeDecider()
        assertEquals(start, d.onHomePress(10_000, true, true))
        assertEquals(start, d.onHomePress(12_001, true, true))
        assertEquals(start, d.onHomePress(60_000, true, true))
    }

    @Test
    fun secondPressWithinTwoSecondsShowsLauncher() {
        val d = HomeDecider()
        assertEquals(start, d.onHomePress(10_000, true, true))
        assertEquals(launcher, d.onHomePress(12_000, true, true))
    }

    @Test
    fun thirdQuickPressStartsANewPair() {
        val d = HomeDecider()
        d.onHomePress(10_000, true, true)
        assertEquals(launcher, d.onHomePress(10_500, true, true))
        assertEquals(start, d.onHomePress(11_000, true, true))
        assertEquals(launcher, d.onHomePress(11_500, true, true))
    }

    @Test
    fun missingKoreaderOrSettingOffShowsLauncher() {
        assertEquals(launcher, HomeDecider().onHomePress(10_000, false, true))
        assertEquals(launcher, HomeDecider().onHomePress(10_000, true, false))
        assertEquals(launcher, HomeDecider().onUncovered(10_000, false, true))
    }

    @Test
    fun uncoveredRestartsKoreaderUnlessItJustStarted() {
        val d = HomeDecider()
        assertEquals(start, d.onHomePress(10_000, true, true))
        // KOReader died 2 s after starting: it isn't staying up.
        assertEquals(launcher, d.onUncovered(12_000, true, true))
        // Killed long after a start (firmware, after sleep): start it again.
        val e = HomeDecider()
        e.onHomePress(10_000, true, true)
        assertEquals(start, e.onUncovered(200_000, true, true))
        // ...and if that start dies at once, the launcher shows.
        assertEquals(launcher, e.onUncovered(201_000, true, true))
    }

    @Test
    fun failedStartIsForgotten() {
        val d = HomeDecider()
        d.onHomePress(10_000, true, true)
        d.startFailed()
        assertEquals(start, d.onUncovered(11_000, true, true))
    }

    @Test
    fun clockGoingBackwardsIsNotADoublePress() {
        val d = HomeDecider()
        d.onHomePress(10_000, true, true)
        assertEquals(start, d.onHomePress(9_000, true, true))
    }
}

class WifiPolicyTest {
    private val now = 1_000_000_000L

    @Test
    fun onlySleepReasonsTouchWifi() {
        for (r in listOf("start", "wake", "retry", "reading", "test", "koreader_wifi_on", "", null, "something_new")) {
            assertNull(r, WifiPolicy.afterSleepSync(WifiAfterSleep.OFF_NOW, r, false, now))
        }
    }

    @Test
    fun defaultIsOffAfterThirtyMinutes() {
        assertEquals(WifiAfterSleep.OFF_AFTER_30, WifiAfterSleep.fromKey(null))
        assertEquals(WifiAfterSleep.OFF_AFTER_30, WifiAfterSleep.fromKey("bogus"))
        assertEquals(
            SleepWifiAction.OffAt(now + 30 * 60_000L),
            WifiPolicy.afterSleepSync(WifiAfterSleep.OFF_AFTER_30, "sleep", false, now),
        )
        // Scheduled with the screen on too: the screen is checked when the timer fires.
        assertEquals(
            SleepWifiAction.OffAt(now + 30 * 60_000L),
            WifiPolicy.afterSleepSync(WifiAfterSleep.OFF_AFTER_30, "sync_and_sleep", true, now),
        )
    }

    @Test
    fun keepOn() {
        assertEquals(SleepWifiAction.KeepOn, WifiPolicy.afterSleepSync(WifiAfterSleep.KEEP_ON, "sleep", false, now))
    }

    @Test
    fun offNowOnlyWithTheScreenOff() {
        assertEquals(SleepWifiAction.OffNow, WifiPolicy.afterSleepSync(WifiAfterSleep.OFF_NOW, "sleep", false, now))
        assertEquals(SleepWifiAction.KeepOn, WifiPolicy.afterSleepSync(WifiAfterSleep.OFF_NOW, "sleep", true, now))
        // Sync and sleep: NET_DONE comes before SLEEP_NOW, so wait for the screen to go off.
        assertEquals(
            SleepWifiAction.OffAtNextScreenOff,
            WifiPolicy.afterSleepSync(WifiAfterSleep.OFF_NOW, "sync_and_sleep", true, now),
        )
    }

    @Test
    fun timerTurnsWifiOffOnlyWithTheScreenStillOff() {
        val deadline = now
        assertEquals(TimerVerdict.TURN_OFF, WifiPolicy.onTimer(now, deadline, screenOn = false, wifiOn = true))
        assertEquals(TimerVerdict.SCREEN_ON, WifiPolicy.onTimer(now, deadline, screenOn = true, wifiOn = true))
        assertEquals(TimerVerdict.ALREADY_OFF, WifiPolicy.onTimer(now, deadline, screenOn = false, wifiOn = false))
        assertEquals(TimerVerdict.NO_TIMER, WifiPolicy.onTimer(now, 0, screenOn = false, wifiOn = true))
        assertEquals(TimerVerdict.NOT_DUE, WifiPolicy.onTimer(now - 60_000, deadline, screenOn = false, wifiOn = true))
        assertEquals(TimerVerdict.TURN_OFF, WifiPolicy.onTimer(now - 2_000, deadline, screenOn = false, wifiOn = true))
    }

    @Test
    fun wakeLockIsCappedAtTwentyFiveSeconds() {
        assertEquals(25_000L, WifiPolicy.wakeLockMs("25", true))
        assertEquals(25_000L, WifiPolicy.wakeLockMs("120", true))
        assertEquals(20_500L, WifiPolicy.wakeLockMs("20.5", true))
        assertEquals(0L, WifiPolicy.wakeLockMs("0", true))
        assertEquals(0L, WifiPolicy.wakeLockMs(null, true))
        assertEquals(0L, WifiPolicy.wakeLockMs("x", true))
        assertEquals(0L, WifiPolicy.wakeLockMs("-3", true))
        assertEquals(0L, WifiPolicy.wakeLockMs("20", false))
    }

    @Test
    fun minutesLeftRoundsUp() {
        assertEquals(30L, WifiPolicy.minutesLeft(now, now + 30 * 60_000L))
        assertEquals(28L, WifiPolicy.minutesLeft(now, now + 27 * 60_000L + 1))
        assertEquals(0L, WifiPolicy.minutesLeft(now, now - 1))
    }

    @Test
    fun sleepNowRateLimit() {
        val r = RateLimiter(5_000)
        assertTrue(r.tryAcquire(10_000))
        assertFalse(r.tryAcquire(12_000))
        assertTrue(r.tryAcquire(15_000))
    }
}

class VersionTest {
    private fun v(s: String) = Version.parse(s)!!

    @Test
    fun parsesTagsAndRejectsJunk() {
        assertEquals(Version(0, 1, 0), Version.parse("v0.1.0"))
        assertEquals(Version(1, 2, 3, "rc.1"), Version.parse("1.2.3-rc.1"))
        assertEquals(Version(1, 2, 3), Version.parse("v1.2.3+build.7"))
        assertNull(Version.parse("1.2"))
        assertNull(Version.parse("latest"))
        assertNull(Version.parse(""))
        assertNull(Version.parse(null))
    }

    @Test
    fun ordersNumericallyNotAsText() {
        assertTrue(v("0.10.0") > v("0.9.9"))
        assertTrue(v("1.0.0") > v("0.99.99"))
        assertTrue(v("0.1.1") > v("0.1.0"))
        assertEquals(0, v("v0.1.0").compareTo(v("0.1.0")))
    }

    @Test
    fun preReleasesSortBeforeTheRelease() {
        assertTrue(v("0.2.0-rc.1") < v("0.2.0"))
        assertTrue(v("0.2.0-rc.1") > v("0.1.9"))
        assertTrue(v("0.2.0-rc.2") > v("0.2.0-rc.1"))
        assertTrue(v("0.2.0-rc.10") > v("0.2.0-rc.9"))
        assertTrue(v("0.2.0-beta") < v("0.2.0-rc"))
        assertTrue(v("0.2.0-rc") < v("0.2.0-rc.1"))
        assertTrue(v("0.0.0-dev") < v("0.1.0"))
    }

    @Test
    fun previewToCandidateToStable() {
        val sequence = listOf("0.11.3-rc.17", "0.11.4-preview.1", "0.11.4-preview.2", "0.11.4-rc.1", "0.11.4").map(::v)
        for ((older, newer) in sequence.zipWithNext()) {
            assertTrue("$older < $newer", older < newer)
            assertTrue("Android installs $newer over $older", older.code < newer.code)
            assertTrue(KoreaderRelease.newer(newer.toString(), older.toString()))
            assertFalse(KoreaderRelease.newer(older.toString(), newer.toString()))
        }
        sequence.forEach { assertEquals(it, NewIn.versionOf(it.code)) }
        assertTrue(v("0.11.4-preview.10") > v("0.11.4-preview.2"))
        assertTrue(v("0.11.4-preview.3999").code < v("0.11.4-rc.1").code)
        assertTrue(v("0.11.4-rc.3999").code < v("0.11.4").code)
        assertTrue(sequence[1].code > 1103) // rc.17's actual legacy code on devices
        assertEquals("0.11.4 Preview 1", sequence[1].display())
        assertEquals("0.11.4 RC 1", sequence[3].display())
        assertEquals("0.11.4", sequence[4].display())
        assertEquals(Version.parse(BuildConfig.VERSION_NAME)!!.code, BuildConfig.VERSION_CODE)
    }

    @Test
    fun versionCodeIsMonotonic() {
        assertEquals(101_009_999, v("0.1.0").code)
        assertEquals(202_039_999, v("1.2.3").code)
        assertTrue(v("0.1.1").code > v("0.1.0").code)
        assertTrue(v("1.0.0").code > v("0.99.99").code)
    }
}

class UpdatePolicyTest {
    private fun r(tag: String, pre: Boolean = false, draft: Boolean = false) = ReleaseInfo(tag, pre, draft, emptyMap())

    @Test
    fun channelVersionMatrixIgnoresGithubFlagAndNeverDowngradesOnSwitch() {
        val cases = mapOf(
            "0.12.0" to listOf(true, true, true),
            "0.12.0+crossink.rc3" to listOf(true, true, true),
            "0.12.0-rc.1" to listOf(false, true, true),
            "0.12.0-rc.20" to listOf(false, true, true),
            "0.13.0-preview.1" to listOf(false, false, true),
            "0.12.0-0.test.99" to listOf(false, false, false),
            "0.12.0-beta.1" to listOf(false, false, false),
            "0.12.0-rc.0" to listOf(false, false, false),
            "0.12.0-preview.01" to listOf(false, false, false),
            "invalid" to listOf(false, false, false),
        )
        for ((version, expected) in cases) for ((i, channel) in UpdateChannel.values().withIndex()) {
            for (flag in listOf(false, true)) {
                assertEquals("$version / $channel / GitHub=$flag", expected[i],
                    UpdatePolicy.pick(listOf(r("v$version", flag)), channel) != null)
            }
        }
        val releases = listOf(r("v0.12.0"), r("v0.13.0-rc.1"), r("v0.14.0-preview.1"))
        for ((i, channel) in UpdateChannel.values().withIndex()) {
            val candidate = UpdatePolicy.pick(releases, channel)!!.version
            assertEquals(releases[i].version, candidate)
            assertFalse(UpdatePolicy.shouldInstall(candidate, Version.parse("0.14.0-preview.1"), emptySet()))
        }
    }

    @Test
    fun newestVersionAllowedByChannelWins() {
        data class Case(val channel: UpdateChannel, val versions: List<String>, val expected: String?,
                        val installed: String = "0.11.0", val install: Boolean = true)
        val cases = listOf(
            Case(UpdateChannel.RC, listOf("0.12.0-rc.3", "0.12.0"), "0.12.0"),
            Case(UpdateChannel.RC, listOf("0.12.0", "0.12.1-preview.2"), "0.12.0"),
            Case(UpdateChannel.RC, listOf("0.12.1-rc.1", "0.12.0"), "0.12.1-rc.1"),
            Case(UpdateChannel.PREVIEW, listOf("0.12.1-preview.3", "0.12.1-rc.1", "0.12.1"), "0.12.1"),
            Case(UpdateChannel.STABLE, listOf("0.12.0", "0.12.1-rc.1", "0.12.1-preview.2"), "0.12.0"),
            Case(UpdateChannel.STABLE, listOf("0.12.1-rc.1", "0.12.1-preview.2"), null, install = false),
            Case(UpdateChannel.RC, listOf("0.12.0", "0.12.1-preview.2"), "0.12.0", "0.12.1-preview.3", false),
            Case(UpdateChannel.STABLE, listOf("0.12.0", "0.12.1-rc.1"), "0.12.0", "0.12.1-rc.1", false),
        )
        for (case in cases) for (versions in listOf(case.versions, case.versions.reversed())) {
            val picked = UpdatePolicy.pick(versions.map { r("v$it", pre = true) }, case.channel)
            assertEquals("$case / $versions", case.expected, picked?.version?.toString())
            assertEquals("$case / $versions", case.install,
                UpdatePolicy.shouldInstall(picked?.version, Version.parse(case.installed), emptySet()))
        }
    }

    @Test
    fun installedRc17SeesPreview1() {
        val release = r("v0.11.4-preview.1", pre = true)
        assertNull(UpdatePolicy.pick(listOf(release), channel = UpdateChannel.STABLE))
        val picked = UpdatePolicy.pick(listOf(release, r("v0.11.3-rc.17", pre = true)), channel = UpdateChannel.PREVIEW)!!
        assertEquals(release, picked)
        assertTrue(UpdatePolicy.isNewer(picked.version, Version.parse("0.11.3-rc.17")))
        assertFalse(TestBuild.isTest(picked.version)) // previews may be published; legacy 0.test builds may not
    }

    @Test
    fun picksNewestStableUnlessPreReleasesWanted() {
        val list = listOf(r("v0.3.0-rc.1", pre = true), r("v0.2.0"), r("v0.4.0", draft = true), r("v0.1.0"), r("nightly"))
        assertEquals("v0.2.0", UpdatePolicy.pick(list, channel = UpdateChannel.STABLE)?.tag)
        assertEquals("v0.3.0-rc.1", UpdatePolicy.pick(list, channel = UpdateChannel.PREVIEW)?.tag)
        assertNull(UpdatePolicy.pick(listOf(r("v1.0.0-rc.1", pre = true)), channel = UpdateChannel.STABLE))
    }

    @Test
    fun withdrawalsSkipAliasesAndAllowRecoveryOnlyFromWithdrawnInstalledVersions() {
        val bad = setOf(Version.parse("0.11.3-rc.10")!!, Version.parse("0.11.3-rc.11")!!)
        val list = listOf(r("v0.11.3-rc.11", true), r("android-v0.11.3-rc.10", true),
            r("v0.11.3-rc.9", true), r("v0.11.2"))
        val candidate = UpdatePolicy.pick(list, UpdateChannel.PREVIEW, bad)!!.version
        assertEquals(Version.parse("0.11.3-rc.9"), candidate)
        assertTrue(UpdatePolicy.shouldInstall(candidate, Version.parse("0.11.3-rc.11"), bad))
        assertFalse(UpdatePolicy.shouldInstall(candidate, Version.parse("0.11.3-rc.12"), bad))
        assertFalse(UpdatePolicy.shouldInstall(Version.parse("0.11.3-rc.11"), Version.parse("0.11.2"), bad))
        assertNull(UpdatePolicy.pick(list.take(2), UpdateChannel.PREVIEW, bad))
        assertEquals("v0.11.2", UpdatePolicy.pick(list, UpdateChannel.STABLE, bad)?.tag)
        assertFalse(UpdatePolicy.shouldInstall(candidate, candidate, bad))
        assertFalse(UpdatePolicy.shouldInstall(null, Version.parse("0.11.3-rc.11"), bad))
    }

    /** shared/fixtures/github/booksync-releases.json: Android and firmware releases in one list. */
    private fun fixture(): List<ReleaseInfo> {
        // @fixture github/booksync-releases.json
        val arr = org.json.JSONArray(java.io.File("../../../shared/fixtures/github/booksync-releases.json").readText())
        return (0 until arr.length()).map { ReleaseInfo.from(arr.getJSONObject(it)) }
    }

    @Test
    fun readsOnlyAndroidTagsFromTheSharedReleaseList() {
        val list = fixture()
        assertEquals("android-v0.7.1", UpdatePolicy.pick(list, channel = UpdateChannel.STABLE)?.tag)
        assertEquals("android-v0.7.2-rc.1", UpdatePolicy.pick(list, channel = UpdateChannel.PREVIEW)?.tag)
        assertNull(list.first { it.tag.startsWith("xteink-v") }.version)
        assertEquals(Version.parse("0.7.0"), list.first { it.tag == "v0.7.0" }.version)
        assertTrue(UpdatePolicy.pick(list, channel = UpdateChannel.STABLE)!!.assets.containsKey("orbit-companion-0.7.1.apk"))
    }

    @Test
    fun releaseTagsForOneVersionTryThePlainTagFirst() {
        assertEquals(listOf("v0.7.0", "android-v0.7.0"), ReleaseTags.forVersion("0.7.0"))
        assertNull(ReleaseTags.version("xteink-v1.6.1.101+bookorbit.8"))
        assertNull(ReleaseTags.version("nightly"))
        assertEquals(Version.parse("0.7.1"), ReleaseTags.version("android-v0.7.1"))
    }

    @Test
    fun aTestBuildIsNeverOfferedAndYieldsToTheNextRelease() {
        val test = Version.parse("0.11.3-0.test.42")!!
        assertTrue(TestBuild.isTest(test))
        assertTrue(TestBuild.isTest("0.11.3-0.test.1"))
        assertFalse(TestBuild.isTest("0.11.3-rc.1"))
        assertFalse(TestBuild.isTest("0.11.3"))
        assertFalse(TestBuild.isTest("0.0.0-dev"))
        // On the test device: the release it was built after is not an update...
        assertFalse(UpdatePolicy.isNewer(Version.parse("0.11.2"), test))
        // ...the next patch's release and every pre-release of it are.
        assertTrue(UpdatePolicy.isNewer(Version.parse("0.11.3"), test))
        assertTrue(UpdatePolicy.isNewer(Version.parse("0.11.3-rc.1"), test))
        assertTrue(UpdatePolicy.isNewer(Version.parse("0.11.3-alpha"), test))
        assertTrue(UpdatePolicy.isNewer(Version.parse("0.11.3-0.test.43"), test))
        // A test version that ever reached a release list is never picked.
        val list = listOf(r("v0.11.3-0.test.42"), r("v0.11.2"), r("v0.11.4-0.test.1", pre = true))
        assertEquals("v0.11.2", UpdatePolicy.pick(list, channel = UpdateChannel.STABLE)?.tag)
        assertEquals("v0.11.2", UpdatePolicy.pick(list, channel = UpdateChannel.PREVIEW)?.tag)
        // It installs over the release it was built after (same or higher versionCode).
        assertTrue(test.code >= Version.parse("0.11.2")!!.code)
    }

    @Test
    fun onlyStrictlyNewerUpdates() {
        assertTrue(UpdatePolicy.isNewer(Version.parse("0.1.1"), Version.parse("0.1.0")))
        assertFalse(UpdatePolicy.isNewer(Version.parse("0.1.0"), Version.parse("0.1.0")))
        assertFalse(UpdatePolicy.isNewer(Version.parse("0.0.9"), Version.parse("0.1.0")))
        assertFalse(UpdatePolicy.isNewer(null, Version.parse("0.1.0")))
        assertTrue(UpdatePolicy.isNewer(Version.parse("0.1.0"), null))
    }

    @Test
    fun checksAtMostDaily() {
        val day = UpdatePolicy.INTERVAL_MS
        assertTrue(UpdatePolicy.due(0, 1_000))
        assertFalse(UpdatePolicy.due(1_000, 1_000 + day - 1))
        assertTrue(UpdatePolicy.due(1_000, 1_000 + day))
        assertTrue(UpdatePolicy.due(5_000, 1_000)) // clock went backwards
    }

    @Test
    fun apkNameFollowsTheReleaseAsset() {
        assertEquals("orbit-companion-0.1.0.apk", UpdatePolicy.apkName(Version.parse("v0.1.0")!!))
    }
}

class ChecksumsTest {
    private val a = "a".repeat(64)
    private val b = "0123456789ABCDEF".repeat(4)

    @Test
    fun parsesSha256sumOutput() {
        val sums = Checksums.parse("$a  orbit-companion-0.1.0.apk\n$b *2-orbit-android.lua\r\n")
        assertEquals(a, sums["orbit-companion-0.1.0.apk"])
        assertEquals(b.lowercase(), sums["2-orbit-android.lua"])
    }

    @Test
    fun skipsBadLines() {
        val sums = Checksums.parse("# comment\n\nabc  short.apk\n${a}x  long.apk\n$a  ok.apk\n")
        assertEquals(1, sums.size)
        assertEquals(a, sums["ok.apk"])
    }
}

class AppStatesTest {
    @Test
    fun frozenIsNotMissing() {
        assertEquals(AppState.MISSING, AppStates.of(false, 0, false, false))
        assertEquals(AppState.OK, AppStates.of(true, 0, true, false))
        assertEquals(AppState.OK, AppStates.of(true, 1, true, false))
        // A vendor launcher's app freeze: enabled=2 (COMPONENT_ENABLED_STATE_DISABLED).
        assertEquals(AppState.FROZEN, AppStates.of(true, 2, false, false))
        assertEquals(AppState.FROZEN, AppStates.of(true, 3, false, false))
        assertEquals(AppState.FROZEN, AppStates.of(true, 4, true, false))
        assertEquals(AppState.FROZEN, AppStates.of(true, 0, true, true))
    }
}

class WifiOwnershipTest {
    @Test
    fun ourRecentRequestIsOursOtherwiseTheUsers() {
        assertEquals(WifiOwner.AUTO, WifiOwnership.onEnabled(10_000, 5_000, WifiOwner.AUTO))
        assertEquals(WifiOwner.MANUAL, WifiOwnership.onEnabled(10_000, 5_000, WifiOwner.MANUAL))
        // Quick settings, long after any request of ours: the user's.
        assertEquals(WifiOwner.MANUAL, WifiOwnership.onEnabled(100_000, 5_000, WifiOwner.AUTO))
        assertEquals(WifiOwner.MANUAL, WifiOwnership.onEnabled(10_000, 0, WifiOwner.AUTO))
    }

    @Test
    fun automaticOffNeverTurnsOffTheUsersWifi() {
        assertFalse(WifiOwnership.allowOff(auto = true, owner = WifiOwner.MANUAL))
        assertTrue(WifiOwnership.allowOff(auto = true, owner = WifiOwner.AUTO))
        assertTrue(WifiOwnership.allowOff(auto = true, owner = WifiOwner.NONE))
        assertTrue(WifiOwnership.allowOff(auto = false, owner = WifiOwner.MANUAL)) // KOReader's own toggle
    }

    @Test
    fun sleepSyncRestoresOffWhenWifiWasOff() {
        val a = WifiPolicy.afterSleepSync(WifiAfterSleep.KEEP_ON, "sleep", screenOn = false, nowWallMs = 0, restoreOff = true)
        assertEquals(SleepWifiAction.OffNow, a)
        val b = WifiPolicy.afterSleepSync(WifiAfterSleep.KEEP_ON, "sync_and_sleep", screenOn = true, nowWallMs = 0, restoreOff = true)
        assertEquals(SleepWifiAction.OffAtNextScreenOff, b)
        assertEquals(SleepWifiAction.KeepOn, WifiPolicy.afterSleepSync(WifiAfterSleep.KEEP_ON, "sleep", false, 0))
    }
}

class SharedSettingsTest {
    @Test
    fun defaultsAndParsing() {
        assertEquals(WifiMode.JIT, WifiMode.fromKey(null))
        assertEquals(WifiMode.OFF_READING, WifiMode.fromKey("off_reading"))
        assertEquals(HomeButton.SMART, HomeButton.fromKey("bogus"))
        assertTrue(SharedSettings.validIdle(5))
        assertFalse(SharedSettings.validIdle(3))
    }
}

class HomeCommandsTest {
    @Test
    fun commandFollowsTheSetting() {
        assertEquals("home_smart", HomeCommands.forPress(HomeButton.SMART))
        assertEquals("home", HomeCommands.forPress(HomeButton.LIBRARY))
        assertEquals("home_smart", HomeCommands.forUncovered(HomeButton.SMART))
        assertEquals(HomeCommands.HOME, HomeCommands.forUncovered(HomeButton.LIBRARY))
    }

    @Test
    fun fromOtherAppOnlyWhenKnown() {
        assertEquals("other_app", HomeCommands.from(companionPageInFront = true, uncovered = false))
        assertEquals("other_app", HomeCommands.from(companionPageInFront = false, uncovered = true))
        assertNull(HomeCommands.from(companionPageInFront = false, uncovered = false))
    }

    @Test
    fun heldRotationNamesTheOrientation() {
        // A portrait reader (Boox Page) held upside down (left-handed): ROTATION_180. Names follow
        // KOReader's launcher (getOrientationCompat), not Android's SCREEN_ORIENTATION_*.
        assertEquals("reverse_portrait", HeldRotation.name(2, naturalPortrait = true))
        assertEquals("portrait", HeldRotation.name(0, naturalPortrait = true))
        assertEquals("reverse_landscape", HeldRotation.name(1, naturalPortrait = true))
        assertEquals("landscape", HeldRotation.name(3, naturalPortrait = true))
        // A panel whose natural orientation is landscape.
        assertEquals("landscape", HeldRotation.name(0, naturalPortrait = false))
        assertEquals("portrait", HeldRotation.name(1, naturalPortrait = false))
        assertEquals("reverse_landscape", HeldRotation.name(2, naturalPortrait = false))
        assertEquals("reverse_portrait", HeldRotation.name(3, naturalPortrait = false))
        assertNull(HeldRotation.name(4, naturalPortrait = true))
    }

    @Test
    fun heldRotationOnlyWithHomeCommands() {
        assertTrue(HeldRotation.sendsWith(HomeCommands.HOME))
        assertTrue(HeldRotation.sendsWith(HomeCommands.HOME_SMART))
        assertFalse(HeldRotation.sendsWith(HomeCommands.RESTART))
        assertFalse(HeldRotation.sendsWith(null))
    }
}

class WifiTestPlanTest {
    @Test
    fun leavesWifiAsFound() {
        assertEquals(listOf(WifiTestPlan.Step.OFF, WifiTestPlan.Step.ON), WifiTestPlan.steps(wasOn = true))
        assertEquals(listOf(WifiTestPlan.Step.ON, WifiTestPlan.Step.OFF), WifiTestPlan.steps(wasOn = false))
    }
}

class VendorProfilesTest {
    private val none: (String) -> Boolean = { false }

    @Test
    fun byManufacturerOrBrand() {
        assertEquals("haoqing", VendorProfiles.pick("Haoqing", "Meebook", none).id)
        assertEquals("onyx", VendorProfiles.pick("ONYX", "Onyx", none).id)
        assertEquals("generic", VendorProfiles.pick("Google", "google", none).id)
        assertEquals("generic", VendorProfiles.pick(null, null, none).id)
    }

    @Test
    fun byLauncherPackageWhenTheBuildSaysNothing() {
        assertEquals("haoqing", VendorProfiles.pick("alps", "alps") { it == "com.haoqing.app.hqreader" }.id)
    }

    @Test
    fun genericHasNoVendorHomeOrHint() {
        assertNull(VendorProfiles.GENERIC.home)
        assertNull(VendorProfiles.GENERIC.launcherPkg)
        assertFalse(VendorProfiles.ONYX.verified)
    }

    @Test
    fun disabledMessageNamesTheDisablerOrStaysNeutral() {
        assertEquals(
            "KOReader is disabled by Meebook Launcher: re-enable it in Meebook Launcher › Freeze management.",
            AppStates.disabledMessage("KOReader", "Meebook Launcher", "Freeze management"),
        )
        assertEquals(
            "KOReader is disabled by the system: re-enable it in Settings › Apps.",
            AppStates.disabledMessage("KOReader", null, null),
        )
        assertEquals("Disabled by the system", AppStates.disabledShort(null))
    }
}

class NetErrorsTest {
    @Test
    fun lockdownSetting() {
        assertEquals(true, NetErrors.lockdown("1"))
        assertEquals(false, NetErrors.lockdown("0"))
        assertNull(NetErrors.lockdown(null))
        assertNull(NetErrors.lockdown("x"))
    }

    @Test
    fun permissionDeniedMeansBlocked() {
        val e = java.net.SocketException("socket failed: EACCES (Permission denied)")
        assertEquals("permission", NetErrors.kindOf(e))
        assertEquals(NetErrors.BLOCKED, NetErrors.message("permission", true, true, lockdown = true, detail = ""))
        assertEquals("permission", NetErrors.kindOf(java.io.IOException("wrap", java.net.SocketException("connect failed: EPERM"))))
    }

    @Test
    fun lockdownBlamedOnlyWhenItReadsOn() {
        assertEquals("connect", NetErrors.kindOf(java.net.UnknownHostException("api.github.com")))
        assertEquals(NetErrors.BLOCKED, NetErrors.message("connect", true, true, lockdown = true, detail = ""))
        // 11-21 Boox: a 15 s connect timeout right after Wi-Fi came up, lockdown reads 0.
        assertEquals(NetErrors.NO_ANSWER, NetErrors.message("connect", true, true, lockdown = false, detail = ""))
        assertEquals(NetErrors.NO_ANSWER, NetErrors.message("connect", true, true, lockdown = null, detail = ""))
        assertEquals("no internet: Android refused the connection (x)", NetErrors.message("permission", true, true, lockdown = false, detail = "x"))
        assertEquals("no internet: Wi-Fi is off", NetErrors.message("connect", false, false, lockdown = true, detail = ""))
    }

    @Test
    fun connectTimeoutOrResetRetriedTwiceAfter3And10s() {
        val slept = mutableListOf<Long>()
        var tries = 0
        val r = NetErrors.withRetry(sleep = { slept += it }) {
            tries++
            if (tries < 3) throw java.net.SocketTimeoutException("failed to connect to api.github.com after 8000ms")
            "ok"
        }
        assertEquals("ok", r)
        assertEquals(3, tries)
        assertEquals(listOf(3_000L, 10_000L), slept)

        slept.clear(); tries = 0
        val e = runCatching {
            NetErrors.withRetry<String>(sleep = { slept += it }) { tries++; throw java.net.SocketException("Connection reset") }
        }.exceptionOrNull()
        assertTrue(e is java.net.SocketException)
        assertEquals(3, tries)
        assertEquals(listOf(3_000L, 10_000L), slept)

        // Not transient: no retry.
        listOf(java.net.SocketException("EACCES (Permission denied)"), java.io.IOException("HTTP 404 from api.github.com"), java.net.UnknownHostException("x")).forEach { ex ->
            slept.clear(); tries = 0
            runCatching { NetErrors.withRetry<String>(sleep = { slept += it }) { tries++; throw ex } }
            assertEquals(1, tries)
            assertTrue(slept.isEmpty())
        }
        assertTrue(NetErrors.CONNECT_TIMEOUT_MS <= 8_000)
    }
}

class PatchFileTest {
    @Test
    fun zipMembersStayInsideThePluginFolder() {
        assertEquals("main.lua", PatchFile.zipMember("orbit.koplugin/main.lua"))
        assertEquals("ko/home.lua", PatchFile.zipMember("orbit.koplugin/ko/home.lua"))
        assertEquals("ko/", PatchFile.zipMember("orbit.koplugin/ko/"))
        for (bad in listOf("main.lua", "orbit.koplugin/", "orbit.koplugin", "other.koplugin/main.lua",
            "orbit.koplugin/../x.lua", "orbit.koplugin/ko/../../x", "orbit.koplugin//x", "orbit.koplugin/./x",
            "orbit.koplugin/a\\b", "/orbit.koplugin/main.lua")) {
            assertNull(bad, PatchFile.zipMember(bad))
        }
    }

    @Test
    fun readsPatchVersion() {
        assertEquals("0.2.2", PatchFile.version("-- x\nlocal PATCH_VERSION = \"0.2.2\"\nlocal y = 1\n"))
        assertNull(PatchFile.version("-- nothing here"))
        assertNull(PatchFile.version(null))
    }

    @Test
    fun installWhenMissingOrOlder() {
        assertTrue(PatchFile.needsInstall(null, "0.2.2"))
        assertTrue(PatchFile.needsInstall("0.2.0", "0.2.2"))
        assertTrue(PatchFile.needsInstall("0.0.0-dev", "0.2.2"))
        assertFalse(PatchFile.needsInstall("0.2.2", "0.2.2"))
        assertFalse(PatchFile.needsInstall("0.3.0", "0.2.2"))
    }
}

class SetupAttentionTest {
    private val v1 = 204
    private fun rows(vararg r: Pair<String, Boolean>) = r.toList()

    @Test
    fun aChangeThatMakesARowNeededPromptsAtOnceEvenWhenSnoozed() {
        val st = SetupAttention.snooze(SetupAttention.State(), listOf("tailscale"), v1)
        val before = SetupAttention.evaluate(rows("tailscale" to false), st, v1)
        assertFalse(before.show)
        val after = SetupAttention.evaluate(rows("tailscale" to false, "clicker" to false), before.next, v1)
        assertEquals(listOf("clicker"), SetupAttention.caused(before.needed, after))
        assertTrue(SetupAttention.caused(after.needed, after).isEmpty())
        assertEquals("keyboard", SetupAttention.idOf("BookSync keyboard enabled"))
    }

    @Test
    fun homePromptsOnceForNewUnsnoozedRows() {
        val r = SetupAttention.evaluate(rows("clicker" to false), SetupAttention.State(), v1)
        assertTrue(SetupAttention.homePrompt(r, emptySet()))
        assertFalse("shown once", SetupAttention.homePrompt(r, setOf("clicker")))
        val more = SetupAttention.evaluate(rows("clicker" to false, "keyboard" to false), r.next, v1)
        assertTrue("a new row prompts again", SetupAttention.homePrompt(more, setOf("clicker")))
        val snoozed = SetupAttention.evaluate(rows("clicker" to false), SetupAttention.snooze(r.next, r.needed, v1), v1)
        assertFalse("Later is respected", SetupAttention.homePrompt(snoozed, emptySet()))
        assertEquals("", SetupAttention.promptKey(snoozed))
        assertEquals("clicker,keyboard", SetupAttention.promptKey(more))
    }

    @Test
    fun idsAreStable() {
        assertEquals("home", SetupAttention.idOf("Set BookSync as Home app"))
        assertEquals("battery:KOReader", SetupAttention.idOf("Battery: Unrestricted (KOReader)"))
        assertEquals("patch", SetupAttention.idOf("KOReader patch installed (v0.2.3)"))
        assertEquals("patch", SetupAttention.idOf("BookSync plugin installed (v0.8.0)"))
        assertEquals("patch_seen", SetupAttention.idOf("BookSync plugin answered"))
        assertEquals("admin", SetupAttention.idOf("Allow \"lock screen\" (device admin)"))
    }

    @Test
    fun allDoneShowsNothingAndInfoRowsNeverPrompt() {
        val r = SetupAttention.evaluate(rows("home" to true, "wifi_test" to false, "patch_seen" to false), SetupAttention.State(), v1)
        assertTrue(r.needed.isEmpty())
        assertFalse(r.show)
    }

    @Test
    fun regressionIsDetectedAndBreaksTheSnooze() {
        var st = SetupAttention.State()
        var r = SetupAttention.evaluate(rows("home" to true, "admin" to false), st, v1)
        assertEquals(listOf("admin"), r.needed)
        assertTrue(r.show)
        st = SetupAttention.snooze(r.next, r.needed, v1)
        r = SetupAttention.evaluate(rows("home" to true, "admin" to false), st, v1)
        assertFalse("snoozed", r.show)
        // Home app changed: a regression, so the prompt is back.
        r = SetupAttention.evaluate(rows("home" to false, "admin" to false), r.next, v1)
        assertEquals(setOf("home"), r.regressed)
        assertTrue(r.show)
    }

    @Test
    fun fixedThenBrokenAgainAlsoBreaksTheSnooze() {
        var r = SetupAttention.evaluate(rows("admin" to false), SetupAttention.State(), v1)
        var st = SetupAttention.snooze(r.next, r.needed, v1)
        r = SetupAttention.evaluate(rows("admin" to true), st, v1)
        assertFalse(r.show)
        r = SetupAttention.evaluate(rows("admin" to false), r.next, v1)
        assertTrue(r.show)
        assertEquals(setOf("admin"), r.regressed)
    }

    @Test
    fun updateEndsTheSnooze() {
        val r = SetupAttention.evaluate(rows("patch" to false), SetupAttention.State(), v1)
        val st = SetupAttention.snooze(r.next, r.needed, v1)
        assertFalse(SetupAttention.evaluate(rows("patch" to false), st, v1).show)
        assertTrue(SetupAttention.evaluate(rows("patch" to false), st, v1 + 1).show)
    }

    @Test
    fun ignoredRowsNeverPromptUntilUndone() {
        var st = SetupAttention.ignore(SetupAttention.State(), "tailscale")
        assertFalse(SetupAttention.evaluate(rows("tailscale" to false), st, v1).show)
        st = SetupAttention.unignoreAll(st)
        assertTrue(SetupAttention.evaluate(rows("tailscale" to false), st, v1).show)
    }

    @Test
    fun whatsNewSinceTheLastSeenVersion() {
        val notes = listOf("0.2.2" to listOf("a"), "0.2.3" to listOf("b"), "0.2.4" to listOf("c"))
        assertEquals(listOf("0.2.3", "0.2.4"), WhatsNew.since(202, 204, notes).map { it.first })
        assertTrue(WhatsNew.since(204, 204, notes).isEmpty())
        assertEquals(listOf("0.2.3", "0.2.4"), WhatsNew.since(202, Version(0, 2, 4).code, notes).map { it.first })
        assertEquals(listOf("0.2.3", "0.2.4"), WhatsNew.since(Version(0, 2, 2).code, Version(0, 2, 4).code, notes).map { it.first })
    }
}

class PatchRowTest {
    @Test
    fun fileDecidesOutdatedRunningDecidesRestart() {
        assertEquals(PatchRowState.MISSING, PatchRow.state(null, null, "0.3.1"))
        assertEquals(PatchRowState.OUTDATED, PatchRow.state("0.3.0", "0.3.0", "0.3.1"))
        // The bug: the file is new, KOReader still runs the old patch -> not "Fix" again.
        assertEquals(PatchRowState.RESTART, PatchRow.state("0.3.1", "0.3.0", "0.3.1"))
        assertEquals(PatchRowState.CURRENT, PatchRow.state("0.3.1", "0.3.1", "0.3.1"))
        assertEquals("running unknown", PatchRowState.CURRENT, PatchRow.state("0.3.1", null, "0.3.1"))
        assertEquals("file unreadable: the running version stands in", PatchRowState.CURRENT, PatchRow.state(null, "0.3.1", "0.3.1"))
        assertEquals(PatchRowState.OUTDATED, PatchRow.state(null, "0.2.4", "0.3.1"))
    }

    @Test
    fun restartCommandOnlyFromPatchesThatKnowIt() {
        assertFalse(PatchRow.canRestart("0.3.0"))
        assertFalse(PatchRow.canRestart(null))
        assertTrue(PatchRow.canRestart("0.3.1"))
        assertTrue(PatchRow.canRestart("0.4.0"))
    }

    @Test
    fun restartIsPendingNotNeedsYou() {
        val st = SetupAttention.State()
        val r = SetupAttention.evaluate(listOf("home" to true, "patch" to true), st, 301, pending = setOf("patch"))
        assertTrue(r.needed.isEmpty())
        assertFalse("no prompt or notification for a restart", r.show)
        assertEquals(listOf("patch"), r.pending)
        assertFalse(SetupAttention.allSet(r))
    }

    @Test
    fun reEvaluatingAfterAnInAppFix() {
        // Prompt open with the outdated patch; Fix installs it (no onResume follows).
        var r = SetupAttention.evaluate(listOf("home" to true, "patch" to false), SetupAttention.State(), 301)
        assertEquals(listOf("patch"), r.needed)
        assertTrue(r.show)
        // Install finished, KOReader still runs the old patch: the row turns into "restart", not "Fix".
        r = SetupAttention.evaluate(listOf("home" to true, "patch" to true), r.next, 301, pending = setOf("patch"))
        assertTrue(r.needed.isEmpty())
        assertEquals(listOf("patch"), r.pending)
        assertFalse(SetupAttention.allSet(r))
        // The new patch reported in: nothing left, the prompt closes with "All set".
        r = SetupAttention.evaluate(listOf("home" to true, "patch" to true), r.next, 301)
        assertTrue(SetupAttention.allSet(r))
        // Restart pending -> outdated again counts as a regression.
        r = SetupAttention.evaluate(listOf("home" to true, "patch" to false), r.next, 301)
        assertEquals(setOf("patch"), r.regressed)
    }
}

class HomeAppTest {
    private val readest = "com.bilingify.readest"

    @Test
    fun anotherAppIsBroughtToTheFrontWithoutKoreaderCommands() {
        val l = HomeApp.launch(readest, press = true, button = HomeButton.SMART, companionPageInFront = false)
        assertEquals(readest, l.pkg)
        assertNull(l.command)
        assertNull(l.from)
        assertEquals("uncovered too", readest, HomeApp.launch(readest, false, HomeButton.SMART, false).pkg)
    }

    @Test
    fun defaultStaysKoreaderWithSmartHome() {
        for (choice in listOf("", HomeApp.KOREADER_PKG, null)) {
            val l = HomeApp.launch(choice, press = true, button = HomeButton.SMART, companionPageInFront = false)
            assertNull(l.pkg)
            assertEquals(HomeCommands.HOME_SMART, l.command)
        }
        assertEquals(HomeCommands.HOME, HomeApp.launch("", true, HomeButton.LIBRARY, false).command)
    }

    @Test
    fun doubleHomeStillShowsTheLauncherForAnotherApp() {
        // The decider is target-neutral: "installed" is the chosen app's state.
        val d = HomeDecider()
        assertEquals(HomeAction.START_KOREADER, d.onHomePress(1_000, true, true))
        assertEquals(HomeAction.SHOW_LAUNCHER, d.onHomePress(2_000, true, true))
        assertEquals("missing app: launcher", HomeAction.SHOW_LAUNCHER, HomeDecider().onHomePress(0, false, true))
    }

    @Test fun everyKoreaderHomeRouteHasAnExplicitCommand() {
        for (choice in listOf(null,"",HomeApp.KOREADER_PKG)) for (button in HomeButton.entries) {
            for (press in listOf(false,true)) for (front in listOf(false,true)) {
                val launch=HomeApp.launch(choice,press,button,front)
                assertNull(launch.pkg)
                assertTrue(launch.command in setOf(HomeCommands.HOME,HomeCommands.HOME_SMART))
            }
        }
    }

    @Test
    fun pickerListsReadersFirstThenAToZWithoutKoreader() {
        val apps = listOf("b.files" to "Files", readest to "Readest", HomeApp.KOREADER_PKG to "KOReader",
            "a.calc" to "calculator", "com.flyersoft.moonreader" to "Moon+ Reader", "com.haoqing.app.hqreader" to "Meebook")
        val readers = KnownApps.readers(VendorProfiles.HAOQING)
        assertEquals(listOf("Meebook", "Moon+ Reader", "Readest", "calculator", "Files"), HomeApp.order(apps, readers).map { it.second })
    }
}

class ReadingScheduleTest {
    @Test
    fun sameOptionsAsThePatch() {
        assertEquals(
            listOf("off", "min10", "min15", "min30", "min60", "pg25", "pg50", "pg100", "ch1", "ch2"),
            ReadingSchedule.OPTIONS.map { it.first },
        )
        assertEquals("Every 2 chapters", ReadingSchedule.label("ch2"))
    }

    @Test
    fun queuedWhileKoreaderIsOffThenAckedByThePatch() {
        // Chosen here with KOReader closed: shown at once, carried in /status until the patch applies it.
        assertEquals("pg50", ReadingSchedule.shown(patchValue = "off", requestId = "pg50"))
        assertEquals("{\"id\":\"pg50\",\"at\":5000}", ReadingSchedule.statusJson("pg50", 5000))
        // The patch's SETTINGS without our request yet (an older applied_at): still pending.
        assertFalse(ReadingSchedule.requestDone("pg50", 5000, appliedAt = 0))
        assertFalse(ReadingSchedule.requestDone("pg50", 5000, appliedAt = null))
        // Applied and saved by the patch: done; the companion then shows the patch's value.
        assertTrue(ReadingSchedule.requestDone("pg50", 5000, appliedAt = 5000))
        assertEquals("null", ReadingSchedule.statusJson("", 0))
        assertEquals("ch1", ReadingSchedule.shown(patchValue = "ch1", requestId = ""))
        assertEquals("off", ReadingSchedule.shown(patchValue = "", requestId = ""))
        assertEquals("null", ReadingSchedule.statusJson("bogus", 1))
    }
}

class HomeOpensTest {
    @Test
    fun toggleOffMigratesToTheLauncherPage() {
        assertEquals(HomeApp.LAUNCHER, HomeApp.migrate("", toggle = false))
        assertEquals(HomeApp.LAUNCHER, HomeApp.migrate("com.example.reader", toggle = false))
        assertEquals("", HomeApp.migrate("", toggle = true))
        assertEquals("com.example.reader", HomeApp.migrate("com.example.reader", toggle = true))
        assertEquals("", HomeApp.migrate("", toggle = null))
    }

    @Test
    fun koreaderChoice() {
        val c = HomeApp.KOREADER_LIBRARY
        assertEquals("koreader", HomeApp.kind(c))
        assertTrue(HomeApp.showsHomeButton(c))
        assertEquals("KOReader + library · press Home twice for the launcher page", HomeApp.summary(c, null))
        assertEquals(HomeAction.START_KOREADER, HomeDecider().onHomePress(0, true, opensApp = true))
        val l = HomeApp.launch(c, press = true, button = HomeButton.SMART, companionPageInFront = false)
        assertEquals(null, l.pkg)
        assertEquals(HomeCommands.HOME_SMART, l.command)
    }

    @Test
    fun launcherPageChoice() {
        val c = HomeApp.LAUNCHER
        assertEquals("launcher", HomeApp.kind(c))
        assertFalse(HomeApp.showsHomeButton(c))
        assertFalse(HomeApp.isKoreader(c))
        assertFalse(HomeApp.isApp(c))
        assertEquals("BookSync launcher page", HomeApp.summary(c, null))
        val d = HomeDecider()
        assertEquals(HomeAction.SHOW_LAUNCHER, d.onHomePress(0, true, opensApp = !HomeApp.isLauncher(c)))
        assertEquals(HomeAction.SHOW_LAUNCHER, d.onUncovered(10_000, true, opensApp = !HomeApp.isLauncher(c)))
    }

    @Test
    fun anotherAppChoice() {
        val c = "com.example.reader"
        assertEquals("app", HomeApp.kind(c))
        assertFalse(HomeApp.showsHomeButton(c))
        assertEquals("Reader · press Home twice for the launcher page", HomeApp.summary(c, "Reader"))
        assertEquals(HomeAction.START_KOREADER, HomeDecider().onHomePress(0, true, opensApp = true))
        assertEquals(HomeApp.Launch(c, null, null), HomeApp.launch(c, press = true, button = HomeButton.SMART, companionPageInFront = false))
    }
}

class UpdateFlowTest {
    @Test
    fun patchFollowsTheAppUpdateOnlyOverAnOlderFile() {
        assertTrue(UpdateFlow.patchAfterUpdate("0.4.9", "0.5.0"))
        assertFalse("already current", UpdateFlow.patchAfterUpdate("0.5.0", "0.5.0"))
        assertFalse("a newer patch-only update is never downgraded", UpdateFlow.patchAfterUpdate("0.5.1", "0.5.0"))
        assertFalse("a first install is Setup's step", UpdateFlow.patchAfterUpdate(null, "0.5.0"))
        assertFalse("a dev build", UpdateFlow.patchAfterUpdate("0.4.9", "dev"))
    }

    @Test
    fun theRunningPatchDecidesWhoRestarts() {
        assertTrue(UpdateFlow.autoRestart("0.5.0"))
        assertTrue(UpdateFlow.autoRestart("0.6.1"))
        assertFalse(UpdateFlow.autoRestart("0.4.9"))
        assertFalse(UpdateFlow.autoRestart(null))
        assertEquals("Updated to v0.5.2; KOReader loads it the next time it starts", UpdateFlow.installedLine("0.5.2"))
        assertEquals("Updated to v0.5.2; KOReader restarts now to load it (an open book reopens)", UpdateFlow.installedLine("0.5.2", now = true))
    }

    /** M8C 11-22 02:06: 0.5.4 -> 0.6.0 by hand; the old process wrote no mark, so it waited for the book. */
    @Test
    fun anAppReplaceRestartsNowWithNoMark() {
        val t = 1_000_000_000L
        val manual = UpdateFlow.restartNowAfter(appReplaced = true, nowMs = t, markAtMs = 0)
        assertTrue("an app replace needs no mark", manual)
        assertEquals("book open: restarts now", UpdateFlow.Restart.NOW, UpdateFlow.restart("0.6.0", "0.5.4", "", manual))
        val patchOnly = UpdateFlow.restartNowAfter(appReplaced = false, nowMs = t, markAtMs = 0)
        assertFalse(patchOnly)
        assertEquals("a background patch-only update waits for the screen-off", UpdateFlow.Restart.WAIT, UpdateFlow.restart("0.6.1", "0.6.0", "", patchOnly))
        assertTrue("a patch-only update the user started", UpdateFlow.restartNowAfter(appReplaced = false, nowMs = t + 1_000, markAtMs = t))
    }

    /** M8C 11-22 01:42: "if I click update myself that means restart KOReader now". */
    @Test
    fun anUpdateYouStartedRestartsWithTheBookOpenAndReopensIt() {
        assertEquals("you started it: now, book open", UpdateFlow.Restart.NOW, UpdateFlow.restart("0.5.5", "0.5.4", "", manual = true))
        assertEquals("a background update waits", UpdateFlow.Restart.WAIT, UpdateFlow.restart("0.5.5", "0.5.4", "", manual = false))
        assertEquals("still once per version", UpdateFlow.Restart.NONE, UpdateFlow.restart("0.5.5", "0.5.4", "0.5.5", manual = true))
        assertEquals(HomeCommands.REOPEN_BOOK, UpdateFlow.relaunchCommand(bookWasOpen = true))
        assertEquals(null, UpdateFlow.relaunchCommand(bookWasOpen = false))
        val t = 1_000_000_000L
        assertTrue("tapped a minute before the replace", UpdateFlow.userStarted(t + 60_000, t))
        assertFalse("never started by hand", UpdateFlow.userStarted(t, 0))
        assertFalse("a stale tap from hours ago", UpdateFlow.userStarted(t + 3 * 3_600_000L, t))
    }

    /**
     * v0.11.1 rule (user decision): a manual update restarts KOReader at once, book open or not;
     * an automatic one never while the screen is on (not with the book closed, not on BookOrbit
     * Home, not on a Home press), only at the screen-off.
     */
    @Test
    fun manualRestartsNowAutomaticOnlyAtScreenOff() {
        assertEquals("manual, a book open: now", UpdateFlow.Restart.NOW, UpdateFlow.restart("0.11.1", "0.11.0", "", manual = true, screenOff = false))
        assertEquals("automatic, the book closed: waits", UpdateFlow.Restart.WAIT, UpdateFlow.restart("0.11.1", "0.11.0", "", manual = false, screenOff = false))
        assertEquals("automatic, a Home press: waits", UpdateFlow.Restart.WAIT, UpdateFlow.restart("0.11.1", "0.11.0", "", manual = false, screenOff = false))
        assertEquals("automatic at the screen-off: now", UpdateFlow.Restart.NOW, UpdateFlow.restart("0.11.1", "0.11.0", "", manual = false, screenOff = true))
        assertEquals("automatic, KOReader never reported: still only at screen-off", UpdateFlow.Restart.WAIT, UpdateFlow.restart("0.11.1", null, "", manual = false))
        assertEquals("sent once per version", UpdateFlow.Restart.NONE, UpdateFlow.restart("0.11.1", "0.11.0", "0.11.1", manual = false, screenOff = true))
        assertEquals("already loaded", UpdateFlow.Restart.NONE, UpdateFlow.restart("0.11.1", "0.11.1", "", manual = true))
        assertEquals("nothing installed", UpdateFlow.Restart.NONE, UpdateFlow.restart("", "0.11.0", "", manual = true))
    }

    /** M8C 11-22 01:42:31: "needs [patch, clicker] (regressed …)" mid-update, notification posted. */
    @Test
    fun setupHoldsItsPromptsWhileAnUpdateSettles() {
        val t = 1_000_000_000L
        assertTrue("version changed, not yet seen", AfterUpdate.settling(t, 0, justUpdated = true, patchBusy = false))
        assertTrue("within the grace", AfterUpdate.settling(t + 10_000, t, justUpdated = false, patchBusy = false))
        assertTrue("patch install or restart running", AfterUpdate.settling(t + 120_000, t, justUpdated = false, patchBusy = true))
        assertFalse("settled", AfterUpdate.settling(t + 31_000, t, justUpdated = false, patchBusy = false))
        assertEquals(setOf("patch", "clicker"), AfterUpdate.pendingRows(true, 120_000, clickerConnected = false))
        assertEquals("clicker reconnected", setOf("patch"), AfterUpdate.pendingRows(true, 120_000, clickerConnected = true))
        assertEquals("a fresh process: the clicker may still be binding", setOf("clicker"), AfterUpdate.pendingRows(false, 5_000, clickerConnected = false))
        assertEquals("after the grace a missing clicker is real", emptySet<String>(), AfterUpdate.pendingRows(false, 60_000, clickerConnected = false))

        // Pending rows are neither needed nor regressed; after the grace a real regression prompts.
        val before = SetupAttention.State(lastDone = setOf("patch", "clicker", "home"))
        val rows = listOf("patch" to false, "clicker" to false, "home" to true)
        val held = SetupAttention.evaluate(rows, before, 10, AfterUpdate.pendingRows(true, 1_000, false))
        assertTrue(held.needed.isEmpty())
        assertTrue(held.regressed.isEmpty())
        assertFalse(held.show)
        val after = SetupAttention.evaluate(listOf("patch" to true, "clicker" to false, "home" to true), held.next, 10, AfterUpdate.pendingRows(false, 60_000, false))
        assertEquals(listOf("clicker"), after.needed)
        assertEquals(setOf("clicker"), after.regressed)
        assertTrue(after.show)
    }

    /** M8C 11-22 01:28-01:34: KOReader ran 0.4.6 with 0.5.3 on disk and nothing pending. */
    @Test
    fun anOlderRunningPatchRestartsOnceAtScreenOff() {
        val s = StaleRestart()
        val lines = mutableListOf<String>()
        assertEquals(UpdateFlow.Restart.NOW, s.decide("0.4.6", "0.5.3", manual = false, screenOff = true) { lines += it })
        assertEquals(listOf("restart: KOReader runs 0.4.6, file has 0.5.3"), lines)
        assertEquals("no loop: still old after the restart", UpdateFlow.Restart.NONE, s.decide("0.4.6", "0.5.3", manual = false, screenOff = true) { lines += it })
        assertEquals("no loop on a manual trigger either", UpdateFlow.Restart.NONE, s.decide("0.4.6", "0.5.3", manual = true, screenOff = false))
        assertEquals(1, lines.size)
        assertEquals("a newer file is a new pair", UpdateFlow.Restart.NOW, s.decide("0.4.6", "0.5.4", manual = false, screenOff = true))
    }

    @Test
    fun anOlderRunningPatchWaitsForTheScreenOff() {
        val s = StaleRestart()
        val lines = mutableListOf<String>()
        assertEquals("status request, screen on", UpdateFlow.Restart.WAIT, s.decide("0.4.6", "0.5.3", manual = false, screenOff = false) { lines += it })
        assertEquals("a Home press", UpdateFlow.Restart.WAIT, s.decide("0.4.6", "0.5.3", manual = false, screenOff = false) { lines += it })
        assertEquals("the wait is logged once", 1, lines.size)
        assertTrue(lines[0].endsWith("or restarts at the next screen-off"))
        assertEquals("after the user's app update", UpdateFlow.Restart.NOW, s.decide("0.4.6", "0.5.3", manual = true, screenOff = false))
        assertEquals(UpdateFlow.Restart.NONE, s.decide("0.4.6", "0.5.3", manual = false, screenOff = true))
    }

    @Test
    fun equalOrNewerRunningPatchDoesNothing() {
        val s = StaleRestart()
        assertEquals(UpdateFlow.Restart.NONE, s.decide("0.5.3", "0.5.3", manual = true, screenOff = true))
        assertEquals("a newer running patch than the file", UpdateFlow.Restart.NONE, s.decide("0.5.4", "0.5.3", manual = true, screenOff = true))
        assertEquals("unknown running", UpdateFlow.Restart.NONE, s.decide(null, "0.5.3", manual = true, screenOff = true))
        assertEquals("no file", UpdateFlow.Restart.NONE, s.decide("0.4.6", null, manual = true, screenOff = true))
        assertEquals("a dev file", UpdateFlow.Restart.NONE, s.decide("0.4.6", "0.0.0-dev", manual = true, screenOff = true))
    }

    /** v0.11.1 (live, plugin 0.10.1 running): Fix next sent signin x3 and recommended x1. */
    @Test
    fun aCommandIsSentOnlyToAPluginThatKnowsIt() {
        assertNull("0.10.1 doesn't know signin", PluginCommands.allowed(HomeCommands.SIGNIN, "0.10.1"))
        assertNull(PluginCommands.allowed(HomeCommands.RECOMMENDED, "0.10.1"))
        assertEquals(HomeCommands.SIGNIN, PluginCommands.allowed(HomeCommands.SIGNIN, "0.11.0"))
        assertEquals(HomeCommands.RECOMMENDED, PluginCommands.allowed(HomeCommands.RECOMMENDED, "0.11.1"))
        assertNull("never reported: a versioned command waits", PluginCommands.allowed(HomeCommands.SIGNIN, null))
        assertNull("restart needs 0.3.1", PluginCommands.allowed(HomeCommands.RESTART, "0.3.0"))
        assertEquals(HomeCommands.RESTART, PluginCommands.allowed(HomeCommands.RESTART, "0.3.1"))
        assertNull("reopen_book needs 0.5.5", PluginCommands.allowed(HomeCommands.REOPEN_BOOK, "0.5.4"))
        assertEquals(HomeCommands.REOPEN_BOOK, PluginCommands.allowed(HomeCommands.REOPEN_BOOK, "0.5.5"))
        assertEquals("home is known by every plugin", HomeCommands.HOME, PluginCommands.allowed(HomeCommands.HOME, null))
        assertEquals(HomeCommands.HOME_SMART, PluginCommands.allowed(HomeCommands.HOME_SMART, "0.1.0"))
        assertNull("no command stays none", PluginCommands.allowed(null, "0.11.0"))
        assertEquals("command=signin not sent: the running plugin (v0.10.1) doesn't know it (needs v0.11.0+)", PluginCommands.droppedLine(HomeCommands.SIGNIN, "0.10.1"))
    }

    /** M8C: command=restart at 21:11:24.559, a Home press 0.9 s later sent command=home and replaced it. */
    @Test
    fun aRestartIsNotReplacedByTheNextStart() {
        val l = RestartLatch()
        val t = 1_000_000L
        assertEquals("nothing sent yet", HomeCommands.HOME, l.resolve(HomeCommands.HOME, t, "0.11.0"))
        l.sent(t, "0.11.0")
        assertEquals("a Home press 0.9 s later sends restart", HomeCommands.RESTART, l.resolve(HomeCommands.HOME_SMART, t + 900, "0.11.0"))
        assertEquals("a plain start too", HomeCommands.RESTART, l.resolve(null, t + 5_000, "0.11.0"))
        assertEquals("a new version runs: the restart happened", HomeCommands.HOME, l.resolve(HomeCommands.HOME, t + 6_000, "0.11.1"))
        l.sent(t, "0.11.0")
        assertEquals("after 10 s it's no longer held", HomeCommands.HOME, l.resolve(HomeCommands.HOME, t + 10_001, "0.11.0"))
        l.sent(t, "0.11.0")
        l.clear() // RELAUNCH came: the plugin read it
        assertEquals("the relaunch's own command goes", HomeCommands.REOPEN_BOOK, l.resolve(HomeCommands.REOPEN_BOOK, t + 2_500, "0.11.0"))
    }

    /** "Nothing interrupts reading": the reading state from STATS (reading=1|0 from 0.11.1, else derived). */
    @Test
    fun readingFromStats() {
        assertEquals(true, ReadingLogic.fromStats("interval", "1", "1"))
        assertEquals("BookOrbit Home over the book", false, ReadingLogic.fromStats("interval", "1", "0"))
        assertEquals("older plugin: open=1", true, ReadingLogic.fromStats("resume", "1", null))
        assertEquals("older plugin: suspend", false, ReadingLogic.fromStats("suspend", "0", null))
        assertEquals("older plugin: closed", false, ReadingLogic.fromStats("close", "0", null))
        assertNull("nothing said", ReadingLogic.fromStats("interval", null, null))
        val t = 1_000_000_000L
        assertTrue(ReadingLogic.reading(t, t + 60_000))
        assertFalse("no report for over 6 min", ReadingLogic.reading(t, t + ReadingLogic.FRESH_MS + 1))
        assertFalse("not reading", ReadingLogic.reading(0, t))
        assertEquals(t + ReadingLogic.FRESH_MS + 1, ReadingLogic.expiresAt(t))
        assertNull(ReadingLogic.expiresAt(0))
    }

    @Test
    fun anUpdateReadyWhileReadingIsHeldUntilTheBookCloses() {
        val g = ReadingGate()
        assertFalse("ready while reading: held", g.offer("update", reading = true, screenOn = true))
        assertEquals(setOf("update"), g.holding)
        assertTrue("still reading: nothing", g.release(reading = true, screenOn = true).isEmpty())
        assertTrue("screen off (suspend): nobody would see it", g.release(reading = false, screenOn = false).isEmpty())
        assertEquals("book closed, screen on: posted", listOf("update"), g.release(reading = false, screenOn = true))
        assertTrue(g.holding.isEmpty())
    }

    @Test
    fun anUpdateReadyOnBookOrbitHomeIsPostedAtOnce() {
        val g = ReadingGate()
        val reading = ReadingLogic.fromStats("interval", "1", "0")!! // Home over the book: reading=0
        assertTrue(g.offer("update", reading, screenOn = true))
        assertTrue(g.holding.isEmpty())
    }

    @Test
    fun nothingIsPostedWithTheScreenOff() {
        val g = ReadingGate()
        assertFalse("screen off: held", g.offer("setup", reading = false, screenOn = false))
        assertTrue(g.release(reading = false, screenOn = false).isEmpty())
        assertFalse(g.offer("update", reading = true, screenOn = true))
        assertTrue("a stale one is dropped", g.drop("setup"))
        assertEquals("in offer order, one per key", listOf("update"), g.release(reading = false, screenOn = true))
    }

    @Test
    fun bookStateFromStatsIgnoresSuspend() {
        assertNull("suspend always says open=0", UpdateFlow.bookFromStats("suspend", "0"))
        assertEquals(true, UpdateFlow.bookFromStats("resume", "1"))
        assertEquals(false, UpdateFlow.bookFromStats("close", "0"))
        assertNull(UpdateFlow.bookFromStats("interval", null))
    }

    @Test
    fun whatsNewIsALineNotANotification() {
        assertEquals("What's new in v0.5.2 ›", WhatsNew.line(true, "0.5.2"))
        assertNull(WhatsNew.line(false, "0.5.2"))
    }

    @Test
    fun oneStatusLineOnceKOReaderRunsTheNewPatch() {
        assertFalse(UpdateFlow.loaded("0.5.1", "0.5.0"))
        assertFalse(UpdateFlow.loaded("0.5.1", null))
        assertTrue(UpdateFlow.loaded("0.5.1", "0.5.1"))
        assertTrue(UpdateFlow.loaded("0.5.1", "0.5.2"))
        assertEquals("Updated to v0.5.1 (KOReader loaded it)", UpdateFlow.doneLine("0.5.1"))
        assertTrue(UpdateFlow.manualLine("0.5.1", "storage access isn't allowed").endsWith("storage access isn't allowed. Setup > BookSync plugin"))
    }
}

/** v0.11.2: one install session at a time; feedback while Android verifies; ABORTED in plain words. */
class UpdateSessionTest {
    private val t0 = 1_000_000L
    private fun st(phase: UpdateSession.Phase) = UpdateSession.State(7, "0.11.2", phase, t0)

    @Test
    fun noSecondSessionWhileOneIsPending() {
        assertTrue("nothing pending", UpdateSession.canCommit(null, alive = false, nowMs = t0))
        assertFalse("committed, still open", UpdateSession.canCommit(st(UpdateSession.Phase.COMMITTED), alive = true, nowMs = t0 + 30_000))
        assertFalse("Android checking", UpdateSession.canCommit(st(UpdateSession.Phase.CHECKING), alive = true, nowMs = t0 + 30_000))
        assertTrue("the session is gone", UpdateSession.canCommit(st(UpdateSession.Phase.CHECKING), alive = false, nowMs = t0 + 30_000))
        assertTrue("no result after 10 min", UpdateSession.canCommit(st(UpdateSession.Phase.CHECKING), alive = true, nowMs = t0 + UpdateSession.STALE_MS))
    }

    @Test
    fun tapsWhilePendingReopenThePromptOrSayAndroidIsChecking() {
        // The M8C case: the 2nd and 3rd taps came while Play Protect was held up.
        assertEquals(UpdateSession.Tap.SAY_CHECKING, UpdateSession.onTap(st(UpdateSession.Phase.CHECKING), alive = true, nowMs = t0 + 10_000))
        assertEquals(UpdateSession.Tap.SAY_CHECKING, UpdateSession.onTap(st(UpdateSession.Phase.COMMITTED), alive = true, nowMs = t0 + 10_000))
        assertEquals(UpdateSession.Tap.REOPEN_PROMPT, UpdateSession.onTap(st(UpdateSession.Phase.PROMPTED), alive = true, nowMs = t0 + 10_000))
        assertEquals(UpdateSession.Tap.NEW_CHECK, UpdateSession.onTap(st(UpdateSession.Phase.CHECKING), alive = false, nowMs = t0 + 10_000))
        assertEquals(UpdateSession.Tap.NEW_CHECK, UpdateSession.onTap(null, alive = false, nowMs = t0))
    }

    @Test
    fun backFromThePromptWithTheSessionOpenMeansAndroidIsChecking() {
        assertEquals(UpdateSession.Phase.CHECKING, UpdateSession.afterPrompt(st(UpdateSession.Phase.PROMPTED), alive = true)!!.phase)
        assertEquals(UpdateSession.Phase.PROMPTED, UpdateSession.afterPrompt(st(UpdateSession.Phase.PROMPTED), alive = false)!!.phase)
        assertEquals(UpdateSession.Phase.COMMITTED, UpdateSession.afterPrompt(st(UpdateSession.Phase.COMMITTED), alive = true)!!.phase)
        assertEquals("Android is checking the update…", UpdateSession.CHECKING)
    }

    @Test
    fun abortedReadsAsCancelledWithARetry() {
        assertEquals("Android cancelled the install; tap to try again",
            UpdateSession.failureLine(3, "INSTALL_FAILED_ABORTED: User rejected permissions", "0.11.1"))
        assertEquals("Android cancelled the install; tap to try again", UpdateSession.failureLine(1, "INSTALL_FAILED_ABORTED", "0.11.1"))
        assertEquals("v0.11.1 install failed (4: INSTALL_FAILED_INVALID_APK)", UpdateSession.failureLine(4, "INSTALL_FAILED_INVALID_APK", "0.11.1"))
    }
}
