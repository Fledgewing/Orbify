// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

import org.junit.Assert.*
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

class RemindersTest {
    private class Memory : Reminders.Store {
        var state=Reminders.State(); var writes=0; var fail=false; var afterCommit=false
        override fun load()=state
        override fun save(state: Reminders.State) { if(fail) throw IllegalStateException("full"); this.state=state; writes++;if(afterCommit) throw IllegalStateException("commit uncertain") }
    }
    private class Fixture {
        val store=Memory(); var wall=Instant.parse("2026-11-27T20:00:00Z").toEpochMilli(); var elapsed=0L
        var zone=ZoneId.of("UTC"); var last=0L; var page=true; var visible=true; var sleep=false; var modal=false; var presenting=false; var owner="A"; var known=true
        var service=Reminders(store,{wall},{elapsed},{zone})
        fun tick(ms: Long=0,input: Boolean=false) { elapsed+=ms; wall+=ms; if(input) last=elapsed; update() }
        fun update()=service.activity(Reminders.Runtime(owner,visible,sleep,page,modal,last,known,presenting))
        fun add(minute:Int=1201,days:Int=127,message:String?=null)=service.add("time",true,minute,days,message,null,"a:${service.revision()}:${UUID.randomUUID()}")
        fun interval(minutes:Int=20) {service.edit(Reminders.INTERVAL,service.records().first {it.id==Reminders.INTERVAL}.revision,"interval",true,null,null,null,minutes,UUID.randomUUID().toString());update()}
        fun read(ms:Long) { var remaining=ms;while(remaining>0) {val step=minOf(remaining,60000);tick(step,true);remaining-=step} }
        fun claim():Reminders.Grant?=service.candidates().firstOrNull()?.let {service.claim(it.event,owner)}
        fun restart() { service=Reminders(store,{wall},{elapsed},{zone});update() }
    }
    private fun invalid(block:()->Unit) {try {block();fail("accepted invalid input")} catch(_:IllegalArgumentException) {}}
    @Test fun defaultsAndSingleton() {
        val f=Fixture();assertEquals(1,f.service.records().size)
        val row=f.service.records().single();assertFalse(row.enabled);assertEquals(20,row.intervalMinutes)
        invalid {f.service.add("interval",true,null,null,null,20,"a")}
        invalid {f.service.delete(row.id,row.revision,"b")}
    }
    @Test fun intervalsAndTaggedFields() {
        val f=Fixture();for(n in listOf(20,30,45,60)) f.interval(n)
        for(n in listOf(-1,0,19,21,61)) invalid {f.interval(n)}
        invalid {f.service.edit(Reminders.INTERVAL,f.service.records().first().revision,"time",true,1200,127,null,null,"x")}
        invalid {f.service.add("time",true,1200,127,null,20,"x")}
        invalid {f.service.edit(Reminders.INTERVAL,f.service.records().first().revision,"interval",true,1200,null,null,20,"x")}
    }
    @Test fun timeValidationAndUnicodeMessage() {
        val f=Fixture()
        for(n in listOf(-1,1440)) invalid {f.add(n)}
        for(n in listOf(0,128,-1)) invalid {f.add(days=n)}
        for(s in listOf("a\nb","a\rb","a\tb","\u0000","\u2028","x".repeat(61),"\ud800")) invalid {f.add(message=s)}
        assertEquals("😀".repeat(60),f.add(message="😀".repeat(60)).message)
        assertEquals("<b>plain</b>",f.add(message="<b>plain</b>").message)
    }
    @Test fun capacityAndMutationReplay() {
        val f=Fixture();val first=f.service.add("time",true,1201,127,null,null,"a:0:same")
        assertEquals(first,f.service.add("time",true,1201,127,null,null,"a:0:same"))
        repeat(7) {f.add()};assertEquals(9,f.service.records().size)
        invalid {f.add()};f.interval(30);assertEquals(9,f.service.records().size)
        f.service.delete(first.id,first.revision,"delete");f.service.delete(first.id,first.revision,"delete")
        assertEquals(8,f.service.records().size)
    }
    @Test fun oldAddReceiptCannotDuplicateAnEditedOrDeletedRecord() {
        val f=Fixture();val key="a:0:create"
        val r=f.service.add("time",true,1201,127,null,null,key)
        val edited=f.service.setEnabled(r.id,1,false,"edit")
        assertEquals(edited,f.service.add("time",true,1201,127,null,null,key))
        f.service.delete(r.id,edited.revision,"delete")
        // Many newer creates/deletes do not require an unbounded tombstone history.
        repeat(20) {val next=f.add();f.service.delete(next.id,1,"delete-$it")}
        invalid {f.service.add("time",true,1201,127,null,null,key)}
        assertEquals(1,f.service.records().size)
    }
    @Test fun revisionsSourcesAndKindsCannotBeForged() {
        val f=Fixture();val r=f.add()
        invalid {f.service.setEnabled(r.id,99,false,"x")}
        invalid {f.service.setEnabled("family:one",1,false,"x")}
        invalid {f.service.delete("family:one",1,"x")}
        invalid {f.service.edit(r.id,1,"interval",true,null,null,null,20,"x")}
        val changed=f.service.setEnabled(r.id,1,false,"off")
        assertEquals(changed,f.service.setEnabled(r.id,1,false,"off"))
    }
    @Test fun ambiguousCommitReconcilesBeforeAnyRetry() {
        val f=Fixture();f.store.afterCommit=true
        val r=f.service.add("time",true,1201,127,null,null,"a:0:create")
        assertEquals(r,f.service.add("time",true,1201,127,null,null,"a:0:create"));assertEquals(1,f.store.writes)
        f.update();f.tick(60000,true);val g=f.claim()!!;assertTrue(f.service.respond(g,"snooze10").accepted)
        assertFalse(f.service.respond(g,"snooze10").accepted);assertEquals(3,f.store.writes)
    }
    @Test fun forwardJumpOffersOnlyCurrentEligibleOccurrence() {
        val f=Fixture();f.add();f.update();f.tick(4*86400000L+120000,true)
        assertEquals("2026-12-01",f.claim()!!.due.original)
    }
    @Test fun saveFailureLeavesScheduleAndRevisionUntouched() {
        val f=Fixture();val r=f.add();val before=f.service.records();f.store.fail=true
        try {f.service.setEnabled(r.id,1,false,"off");fail()} catch(_:IllegalStateException) {}
        assertEquals(before,f.service.records())
        try {f.service.delete(r.id,1,"delete");fail()} catch(_:IllegalStateException) {}
        assertEquals(before,f.service.records())
    }
    @Test fun enablingAndEditingNeverBackfire() {
        val f=Fixture();f.add(1199);f.update();assertTrue(f.service.candidates().isEmpty())
        val r=f.add();f.tick(120000,true)
        f.service.edit(r.id,1,"time",true,1201,127,null,null,"edit");assertTrue(f.service.candidates().isEmpty())
    }
    @Test fun dueWithoutInputAndClaimIsDurableBeforeDraw() {
        val f=Fixture();f.add();f.update();f.tick(60000)
        val g=f.claim()!!;assertEquals("2026-11-27",f.store.state.records.first {it.id==g.due.id}.highWater)
        assertTrue(f.service.drawable(g));assertNull(f.service.claim(g.due.event,"A"))
        f.restart();assertTrue(f.service.candidates().isEmpty())
    }
    @Test fun failedClaimNeverGrants() {
        val f=Fixture();f.add();f.update();f.tick(60000);f.store.fail=true
        try {f.claim();fail()} catch(_:IllegalStateException) {}
        assertNull(f.store.state.records.first {it.kind=="time"}.highWater)
        f.store.fail=false;assertNotNull(f.claim())
    }
    @Test fun missedInclusiveBoundaryAndPreviousDate() {
        for(late in listOf(0L,59999L,60000L,3600000L,3601000L)) {
            val f=Fixture();f.add();f.update();f.tick(60000+late,true)
            val due=f.service.candidates().firstOrNull();assertEquals(late<=3600000,due!=null)
            if(due!=null) assertEquals(late>=60000,due.missed)
        }
        val f=Fixture();f.add(1439);f.update();f.tick(4*60*60000L+60000,true)
        assertEquals("2026-11-27",f.claim()!!.due.original)
    }
    @Test fun homeAndMenuAllowTimeButNeverHiddenOrSleeping() {
        for(state in listOf("home","menu","hidden","sleep")) {
            val f=Fixture();f.add();f.update();f.page=false
            if(state=="hidden") f.visible=false
            if(state=="sleep") f.sleep=true
            f.tick(60000,true);assertEquals(state in listOf("home","menu"),f.claim()!=null)
        }
    }
    @Test fun clockUnknownHoldsTime() {
        val f=Fixture();f.add();f.known=false;f.update();f.tick(60000,true);assertNull(f.claim())
        f.known=true;f.update();assertNotNull(f.claim())
    }
    @Test fun backwardClockAndRepeatedTicksNeverRepeatClaim() {
        val f=Fixture();f.add();f.update();f.tick(60000,true);val g=f.claim()!!
        assertTrue(f.service.respond(g,"gotIt").accepted)
        f.wall-=30000;f.tick(60000,true);assertNull(f.claim())
        f.restart();assertNull(f.claim())
    }
    @Test fun occurrenceDaySurvivesRevisionChanges() {
        val f=Fixture();val r=f.add();f.update();f.tick(60000,true);val g=f.claim()!!;f.service.respond(g,"gotIt")
        f.service.edit(r.id,1,"time",true,1202,127,null,null,"edit")
        f.tick(60000,true);assertNull(f.claim())
    }
    @Test fun snoozeRepeatsAndUsesElapsedAcrossWallCorrection() {
        val f=Fixture();f.add();f.update();f.tick(60000,true)
        repeat(3) {n ->
            val g=f.claim()!!;assertEquals(n,g.due.sequence);assertTrue(f.service.respond(g,"snooze10").accepted)
            f.wall+=7200000;f.tick(599999,true);assertNull(f.claim());f.tick(1,true)
        }
        assertEquals(3,f.claim()!!.due.sequence)
    }
    @Test fun snoozeGrantUsesElapsedExpiryAcrossAClockCorrection() {
        val f=Fixture();f.add();f.update();f.tick(60000,true);f.service.respond(f.claim()!!,"snooze10")
        f.tick(600000,true);val g=f.claim()!!;f.wall+=86400000
        assertTrue(f.service.drawable(g));f.elapsed+=3600001
        assertFalse(f.service.drawable(g));assertFalse(f.service.respond(g,"sleep",true).sleep)
        f.service.retire(g);assertFalse(f.service.valid(g))
    }
    @Test fun snoozeRestartUsesWallAndKnownClock() {
        val f=Fixture();f.add();f.update();f.tick(60000,true);f.service.respond(f.claim()!!,"snooze10")
        f.tick(600000,true);f.known=false;f.restart();assertNull(f.claim())
        f.known=true;f.update();assertEquals(1,f.claim()!!.due.sequence)
    }
    @Test fun snoozeAfterMidnightDoesNotRetestDay() {
        val f=Fixture();f.add(1439,16);f.update();f.tick((3*60+59)*60000L,true)
        f.service.respond(f.claim()!!,"snooze10");f.tick(600000,true);assertEquals("2026-11-27",f.claim()!!.due.original)
    }
    @Test fun editsAndDisableInvalidateSnoozeAndGrants() {
        val f=Fixture();val r=f.add();f.update();f.tick(60000,true);val g=f.claim()!!
        f.service.setEnabled(r.id,1,false,"off");assertFalse(f.service.valid(g));assertFalse(f.service.respond(g,"sleep",true).accepted)
        f.tick(600000,true);assertNull(f.claim())
    }
    @Test fun respondDuplicateNeverRepeatsNativeSleep() {
        val f=Fixture();f.add();f.update();f.tick(60000,true);val g=f.claim()!!
        assertFalse(f.service.respond(g,"sleep",false).accepted);assertTrue(f.service.valid(g))
        assertTrue(f.service.respond(g,"sleep",true).sleep)
        assertFalse(f.service.respond(g,"sleep",true).sleep)
    }
    @Test fun failedSleepCheckpointStillAllowsDismissOrSnoozeWithoutAnotherSleepIntent() {
        for(action in listOf("gotIt","snooze10")) {
            val f=Fixture();f.add();f.update();f.tick(60000,true);val g=f.claim()!!
            f.presenting=true;f.update()
            assertTrue(f.service.respond(g,"sleep",true).sleep)
            val writes=f.store.writes
            assertTrue(f.service.valid(g))
            assertFalse(f.service.respond(g,"sleep",true).sleep)
            assertEquals(writes,f.store.writes)
            if(action=="snooze10") {
                f.store.fail=true
                try {f.service.respond(g,action);fail()} catch(_:IllegalStateException) {}
                assertTrue(f.service.valid(g));f.store.fail=false
            }
            assertTrue(f.service.respond(g,action).accepted)
            assertFalse(f.service.valid(g));assertFalse(f.service.respond(g,"sleep",true).sleep)
            f.presenting=false;f.update();f.tick(600000,true)
            assertEquals(action=="snooze10",f.claim()!=null)
        }
    }
    @Test fun wrongKindActionsRejected() {
        val f=Fixture();f.add();f.update();f.tick(60000,true);val g=f.claim()!!
        for(action in listOf("done","turnOff","lock","close")) invalid {f.service.respond(g,action)}
    }
    @Test fun responseFailureKeepsSheetAndNoSnoozeSuccess() {
        val f=Fixture();f.add();f.update();f.tick(60000,true);val g=f.claim()!!;f.store.fail=true
        try {f.service.respond(g,"snooze10");fail()} catch(_:IllegalStateException) {}
        assertTrue(f.service.valid(g));assertNull(f.store.state.records.first {it.kind=="time"}.snooze)
        f.store.fail=false;assertTrue(f.service.respond(g,"snooze10").accepted)
    }
    @Test fun dismissalRequiresFreshInputBeforeWaitingSheet() {
        val f=Fixture();repeat(2) {f.add()};f.update();f.tick(60000,true)
        f.service.respond(f.claim()!!,"gotIt");f.tick(1);assertNull(f.claim())
        f.tick(1,true);assertNotNull(f.claim())
    }
    @Test fun lateDrawExpiresButVisibleSheetCanStillRespond() {
        val f=Fixture();f.add();f.update();f.tick(60000,true);val g=f.claim()!!
        f.presenting=true;f.update();f.tick(3601000,true);assertFalse(f.service.drawable(g));assertTrue(f.service.respond(g,"gotIt").accepted)
    }
    @Test fun undrawnGrantTimeoutCannotBlockOtherRemindersOrDrawLate() {
        val f=Fixture();repeat(2) {f.add()};f.update();f.tick(60000,true);val g=f.claim()!!
        f.tick(120001,true);assertFalse(f.service.valid(g));assertFalse(f.service.drawable(g));assertNull(f.claim())
        f.tick(1,true);assertNotEquals(g.due.id,f.claim()!!.due.id)
    }
    @Test fun ownerAtoBtoANeverRevivesGrant() {
        val f=Fixture();f.add();f.update();f.tick(60000,true);val g=f.claim()!!
        f.owner="B";f.update();f.owner="A";f.update();assertFalse(f.service.valid(g));assertNull(f.claim())
    }
    @Test fun retirementRechecksHiddenSleepAndOtherModal() {
        for(transition in listOf("hidden","sleep","modal")) {
            val f=Fixture();f.add();f.update();f.tick(60000,true);val g=f.claim()!!
            when(transition) {"hidden"->f.visible=false;"sleep"->f.sleep=true;else->f.modal=true};f.update()
            assertFalse(f.service.drawable(g));assertFalse(f.service.respond(g,"sleep",true).sleep)
        }
    }
    @Test fun intervalThresholdsAndNoTickOrDoneWrites() {
        for(n in listOf(20,30,45,60)) {
            val f=Fixture();f.interval(n);val writes=f.store.writes
            f.read(n*60000L-1);assertNull(f.claim());f.tick(1,true);val g=f.claim()!!
            assertEquals("interval",g.due.kind);assertEquals(writes,f.store.writes)
            assertTrue(f.service.respond(g,"done").accepted);assertEquals(writes,f.store.writes)
            assertFalse(f.service.respond(g,"done").accepted);f.read(n*60000L-1);assertNull(f.claim())
            f.tick(1,true);assertNotNull(f.claim())
        }
    }
    @Test fun lifecycleCaptureTimeExcludesPausedTimeEvenIfWorkerRunsAfterResume() {
        val f=Fixture();f.interval();f.read(19*60000L)
        val start=f.elapsed;f.elapsed+=120000;f.wall+=120000
        f.service.activity(Reminders.Runtime("A",true,false,false,false,start,at=start))
        f.service.activity(Reminders.Runtime("A",true,false,true,false,f.elapsed,at=f.elapsed))
        assertNull(f.claim());f.last=f.elapsed;f.read(60000);assertNotNull(f.claim())
    }
    @Test fun intervalPauseFourFiftyNinePreservesAndFiveResets() {
        for(gap in listOf(299999L,300000L)) {
            val f=Fixture();f.interval();f.read(19*60000L);f.page=false;f.update();f.tick(gap)
            f.page=true;f.tick(0,true);f.read(60000)
            assertEquals(gap<300000,f.claim()!=null)
        }
    }
    @Test fun idleGapContinuesAcrossShortMenuHiddenAndSleepPausesBeforeResumeInput() {
        for(mode in listOf("menu","hidden","sleep")) {
            val f=Fixture();f.interval();f.read(15*60000L);f.tick(4*60000L)
            when(mode) {"menu"->f.page=false;"hidden"->f.visible=false;else->f.sleep=true};f.update()
            f.tick(60000);f.page=true;f.visible=true;f.sleep=false;f.tick(0,true)
            f.read(60000);assertNull(mode,f.claim())
            f.read(19*60000L);assertNotNull(mode,f.claim())
        }
    }
    @Test fun idleBoundaryResetsBeforeDueEvenWithResumeInput() {
        val f=Fixture();f.interval();f.read(19*60000L);f.tick(300000,true);assertNull(f.claim())
        f.read(19*60000L);assertNull(f.claim());f.read(60000);assertNotNull(f.claim())
    }
    @Test fun idleBoundaryWithoutInputDoesNotFire() {
        val f=Fixture();f.interval();f.read(19*60000L);f.tick(300000);assertNull(f.claim())
    }
    @Test fun everyNonPageStatePausesAndRetiresUndrawnInterval() {
        for(mode in listOf("home","menu","hidden","closed","sleep","modal")) {
            val f=Fixture();f.interval();f.read(20*60000L);val event=f.service.candidates().single()
            when(mode) {"hidden"->f.visible=false;"sleep"->f.sleep=true;"modal"->f.modal=true;else->f.page=false};f.update()
            assertNull(f.service.claim(event.event,"A"));f.visible=true;f.sleep=false;f.modal=false;f.page=true;f.tick(1,true)
            assertNull(f.claim());f.read(20*60000L);assertNotNull(f.claim())
        }
    }
    @Test fun menuAtThresholdBeforePublicationConsumesInterval() {
        val f=Fixture();f.interval();f.read(19*60000L);f.page=false;f.tick(60000,true)
        f.page=true;f.tick(1,true);assertNull(f.claim());f.read(20*60000L);assertNotNull(f.claim())
    }
    @Test fun unknownClockAndJumpsDoNotAffectInterval() {
        val f=Fixture();f.interval();f.known=false;f.wall-=100000000;f.zone=ZoneId.of("Asia/Tokyo");f.read(20*60000L)
        assertEquals("interval",f.claim()!!.due.kind)
    }
    @Test fun restartResetsIntervalWithoutPersistingHistory() {
        val f=Fixture();f.interval();f.read(19*60000L);f.restart();f.read(60000);assertNull(f.claim())
        f.read(19*60000L);assertNotNull(f.claim())
    }
    @Test fun intervalEditStartsFullNewInterval() {
        val f=Fixture();f.interval();f.read(19*60000L);f.interval(30);f.read(29*60000L);assertNull(f.claim())
        f.read(60000);assertNotNull(f.claim())
    }
    @Test fun intervalTurnOffDurableOrLeavesEnabledAndSheet() {
        val f=Fixture();f.interval();f.read(20*60000L);val g=f.claim()!!;f.store.fail=true
        try {f.service.respond(g,"turnOff");fail()} catch(_:IllegalStateException) {}
        assertTrue(f.service.valid(g));assertTrue(f.service.records().single().enabled)
        f.store.fail=false;assertTrue(f.service.respond(g,"turnOff").accepted);f.restart();assertFalse(f.service.records().single().enabled)
    }
    @Test fun visibleEyeSheetNeverHasAnIdleTimedClose() {
        val f=Fixture();f.interval();f.read(20*60000L);val g=f.claim()!!
        f.presenting=true;f.update();f.tick(10*60000L)
        assertTrue(f.service.valid(g));assertTrue(f.service.respond(g,"done").accepted)
    }
    @Test fun intervalRejectsTimeActions() {
        val f=Fixture();f.interval();f.read(20*60000L);val g=f.claim()!!
        for(a in listOf("sleep","snooze10","gotIt")) invalid {f.service.respond(g,a,true)}
    }
    @Test fun bedtimeWinsBothEvaluationOrdersAndConsumesInterval() {
        for(first in listOf(true,false)) {
            val f=Fixture();f.interval();f.add(1220);f.read(19*60000L)
            if(first) f.service.candidates()
            f.read(60000);val candidates=f.service.candidates();assertEquals("time",candidates.first().kind)
            f.service.respond(f.claim()!!,"gotIt");f.tick(1,true);assertNull(f.claim())
            f.read(20*60000L);assertEquals("interval",f.claim()!!.due.kind)
        }
    }
    @Test fun bedtimeSnoozeAlsoWins() {
        val f=Fixture();f.interval();f.add(1210);f.read(10*60000L);f.service.respond(f.claim()!!,"snooze10")
        f.read(10*60000L);assertEquals("time",f.claim()!!.due.kind)
    }
    @Test fun visibleIntervalIsNeverReplacedByBedtime() {
        val f=Fixture();f.interval();f.add(1221);f.read(20*60000L);val g=f.claim()!!
        f.tick(60000,true);assertTrue(f.service.valid(g));assertTrue(f.service.candidates().isEmpty())
        f.service.respond(g,"done");f.tick(1,true);assertEquals("time",f.claim()!!.due.kind)
    }
    @Test fun recurrenceMasksLeapDayAndMidnight() {
        val zone=ZoneId.of("UTC")
        assertEquals(Instant.parse("2028-02-29T00:00:00Z").toEpochMilli(),Reminders.scheduled(LocalDate.parse("2028-02-29"),0,zone))
        for(mask in listOf(127,31,96,1,16,64)) {
            val f=Fixture();f.add(days=mask);f.update();f.tick(60000,true)
            assertEquals(mask and 16!=0,f.claim()!=null)
        }
    }
    @Test fun dstGapFirstValidMinuteAndOverlapFirstInstant() {
        val zone=ZoneId.of("America/Los_Angeles")
        assertEquals(Instant.parse("2026-03-08T10:00:00Z").toEpochMilli(),Reminders.scheduled(LocalDate.parse("2026-03-08"),150,zone))
        assertEquals(Instant.parse("2026-11-01T08:30:00Z").toEpochMilli(),Reminders.scheduled(LocalDate.parse("2026-11-01"),90,zone))
    }
    @Test fun timeInputUsesDeviceFormatAndRejectsInvalidFields() {
        assertEquals(0,Reminders.parseTime("12:00 AM",true));assertEquals(720,Reminders.parseTime("12:00 PM",true))
        assertEquals(1260,Reminders.parseTime("9:00 PM",true));assertEquals(1260,Reminders.parseTime("21:00",false))
        assertEquals(1439,Reminders.parseTime("23:59",false))
        for(input in listOf("24:00","-1:00","12:60","20:01 PM","12:01:00","1:1","NaN","<b>21:00</b>")) invalid {Reminders.parseTime(input,false)}
        for(input in listOf("00:00 AM","13:00 PM","9:00","9:00 XX","9:60 PM")) invalid {Reminders.parseTime(input,true)}
    }
    @Test fun formattingIsDisplayOnlyAndBounded() {
        val f=Fixture();repeat(8) {f.add(1260,message="😀".repeat(60))};val before=f.store.state
        assertEquals(true,f.service.snapshot(true)["twelveHour"]);assertEquals(false,f.service.snapshot(false)["twelveHour"])
        assertTrue(f.service.snapshot(true,java.util.Locale.US).toString().contains("9:00 PM"))
        assertTrue(f.service.snapshot(false).toString().contains("21:00"));assertEquals(before,f.store.state)
        assertTrue(LuaValue.encode(f.service.snapshot(false)).size<=8192)
    }
}
