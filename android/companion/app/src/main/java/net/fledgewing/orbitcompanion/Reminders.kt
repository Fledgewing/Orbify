// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

/** Device-local reminder policy. One serialized worker owns this service; UI only sends
 * neutral intents. Wall time is milliseconds; elapsed time must include suspend. */
class Reminders(private val store: Store, private val wall: () -> Long,
                private val elapsed: () -> Long, private val zone: () -> ZoneId,
                private val token: () -> String = { UUID.randomUUID().toString() }) {
    interface Store {
        fun load(): State
        /** Atomic and durable, or throw. Never publish a speculative state. */
        fun save(state: State)
    }
    data class Record(val id: String, val kind: String, val revision: Long = 1,
        val enabled: Boolean = false, val minuteOfDay: Int? = null, val days: Int? = null,
        val message: String? = null, val intervalMinutes: Int? = null,
        val after: Long = 0, val highWater: String? = null, val snooze: Snooze? = null,
        val mutation: String? = null, val response: String? = null) {
        val source get() = "local"
    }
    data class Snooze(val original: String, val due: Long, val sequence: Int)
    data class State(val records: List<Record> = listOf(Record(INTERVAL, "interval", intervalMinutes=20)),
        val deletedId: String? = null, val deletion: String? = null, val generation: Long = 0)
    data class Runtime(val owner: String, val visible: Boolean, val sleeping: Boolean,
        val page: Boolean, val modal: Boolean, val lastInput: Long, val knownClock: Boolean = true, val presenting: Boolean = false, val at: Long? = null)
    data class Due(val event: String, val id: String, val revision: Long, val kind: String,
        val original: String, val due: Long, val expiry: Long, val sequence: Int = 0,
        val session: String? = null, val missed: Boolean = false, val elapsedExpiry: Long? = null)
    data class Grant(val token: String, val owner: String, val due: Due, val issuedAt: Long)
    data class Response(val accepted: Boolean, val sleep: Boolean = false)
    companion object {
        const val INTERVAL = "local:eye-rest"
        const val EYE_TEXT = "Rest your eyes. Look at something far away for 20 seconds."
        const val DEFAULT_TEXT = "Time to stop reading"
        const val MINUTE = 60000L
        const val BREAK = 5 * MINUTE
        const val WINDOW = 60 * MINUTE
        val INTERVALS = setOf(20,30,45,60)
        fun validate(r: Record) {
            require(r.id==INTERVAL || r.id.matches(Regex("local:[0-9a-f-]{36}")))
            require(r.revision in 1..9007199254740991L && r.after>=0)
            require(r.mutation==null || r.mutation.length in 1..64)
            require(r.response==null || r.response.length in 1..128)
            if(r.highWater!=null) { require(r.highWater.matches(Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}"))); LocalDate.parse(r.highWater) }
            r.snooze?.let { require(it.original.length in 1..80 && it.due>=0 && it.sequence in 1 until Int.MAX_VALUE) }
            when(r.kind) {
                "time" -> {
                    require(r.id!=INTERVAL && r.minuteOfDay in 0..1439 && r.days in 1..127 && r.intervalMinutes==null)
                    val s=r.message ?: ""
                    require(s.codePointCount(0,s.length)<=60 && s.toByteArray(Charsets.UTF_8).size<=240)
                    require(s.codePoints().noneMatch { Character.isISOControl(it) || it==0x2028 || it==0x2029 || it in 0xd800..0xdfff })
                }
                "interval" -> require(r.id==INTERVAL && r.intervalMinutes in INTERVALS && r.minuteOfDay==null && r.days==null && r.message==null && r.highWater==null && r.snooze==null)
                else -> throw IllegalArgumentException("kind")
            }
        }
        fun validate(s: State) {
            require(s.generation in 0..9007199254740990L)
            require(s.records.size in 1..9 && s.records.count {it.kind=="time"}<=8 && s.records.count {it.id==INTERVAL}==1)
            require(s.records.map {it.id}.distinct().size==s.records.size)
            s.records.forEach(::validate)
            require(s.deletion==null || s.deletion.length in 1..64)
            require((s.deletion==null)==(s.deletedId==null))
            require(s.deletedId==null || s.deletedId.matches(Regex("local:[0-9a-f-]{36}")))
        }
        fun parseTime(input: String, twelveHour: Boolean): Int {
            val pattern=if(twelveHour) Regex("([0-9]{1,2}):([0-9]{2}) (AM|PM)",RegexOption.IGNORE_CASE) else Regex("([0-9]{1,2}):([0-9]{2})")
            val match=pattern.matchEntire(input.trim()) ?: throw IllegalArgumentException("time")
            val hour=match.groupValues[1].toInt();val minute=match.groupValues[2].toInt()
            require(minute in 0..59 && hour in if(twelveHour) 1..12 else 0..23)
            val h=if(twelveHour) hour%12+(if(match.groupValues[3].equals("PM",true)) 12 else 0) else hour
            return h*60+minute
        }
        /** Gaps use their first valid minute, overlaps their first instant. */
        fun scheduled(date: LocalDate, minute: Int, zone: ZoneId): Long {
            val local=date.atStartOfDay().plusMinutes(minute.toLong())
            val offsets=zone.rules.getValidOffsets(local)
            return if(offsets.isEmpty()) zone.rules.getTransition(local)!!.dateTimeAfter.atZone(zone).toInstant().toEpochMilli()
                else local.toInstant(offsets.first()).toEpochMilli()
        }
    }
    private var state=store.load().also(::validate)
    private var runtime: Runtime?=null
    private var previousAt=elapsed()
    private var gapAt: Long?=null
    private var activeMs=0L
    private var session=token()
    private var sequence=0
    private var intervalDue: Due?=null
    private var grant: Grant?=null
    private var waitForInput: Long?=null
    private val snoozeElapsed=mutableMapOf<String,Pair<Int,Long>>()
    private var storageUnknown=false
    private fun persist(next: State) {
        check(!storageUnknown)
        validate(next)
        try {store.save(next)} catch(e:Exception) {
            // An OS commit error may be reported after publication. Reconcile the
            // bounded durable record before another claim or idempotent retry.
            val durable=runCatching {store.load().also(::validate)}
            if(durable.isFailure) {storageUnknown=true;throw e}
            state=durable.getOrThrow()
            if(state!=next) throw e
        }
        state=next
    }
    fun storageReady(): Boolean = !storageUnknown
    fun revision(): Long = state.generation
    fun records(): List<Record> = state.records.toList()
    private fun record(id: String)=state.records.firstOrNull {it.id==id} ?: throw IllegalArgumentException("missing")
    private fun key(value: String) = require(value.length in 1..64)
    private fun resetInterval() { activeMs=0; intervalDue=null; session=token(); sequence=0 }
    private fun changed(id: String) {
        snoozeElapsed.remove(id)
        if(grant?.due?.id==id) grant=null
        if(id==INTERVAL) { resetInterval(); previousAt=elapsed() }
    }
    fun add(kind: String, enabled: Boolean, minute: Int?, days: Int?, message: String?, interval: Int?, mutation: String): Record {
        key(mutation); require(kind=="time")
        val id="local:"+UUID.nameUUIDFromBytes(("booksync-reminder:"+mutation).toByteArray(Charsets.UTF_8))
        state.records.firstOrNull {it.id==id}?.let { return it }
        val base=Regex("a:([0-9]+):.{1,40}").matchEntire(mutation)?.groupValues?.get(1)?.toLongOrNull()
        require(base==state.generation) { "conflict" }
        require(state.records.count {it.kind=="time"}<8) { "limit" }
        val r=Record(id,kind,enabled=enabled,minuteOfDay=minute,days=days,message=message,
            intervalMinutes=interval,after=wall(),mutation=mutation)
        validate(r); persist(state.copy(records=state.records+r,generation=state.generation+1)); return r
    }
    fun edit(id: String, revision: Long, kind: String, enabled: Boolean, minute: Int?, days: Int?, message: String?, interval: Int?, mutation: String): Record {
        key(mutation); val old=record(id)
        if(old.mutation==mutation) return old
        require(old.revision==revision) { "conflict" }; require(old.kind==kind)
        val r=old.copy(revision=revision+1,enabled=enabled,minuteOfDay=minute,days=days,message=message,
            intervalMinutes=interval,after=wall(),snooze=null,mutation=mutation,response=null)
        validate(r); persist(state.copy(records=state.records.map {if(it.id==id) r else it},generation=state.generation+1)); changed(id); return r
    }
    fun setEnabled(id: String, revision: Long, enabled: Boolean, mutation: String): Record {
        val r=record(id)
        return edit(id,revision,r.kind,enabled,r.minuteOfDay,r.days,r.message,r.intervalMinutes,mutation)
    }
    fun delete(id: String, revision: Long, mutation: String) {
        key(mutation)
        if(state.deletedId==id && state.deletion==mutation) return
        val r=record(id); require(r.kind=="time" && r.revision==revision)
        persist(state.copy(records=state.records.filter {it.id!=id},deletedId=id,deletion=mutation,generation=state.generation+1)); changed(id)
    }
    /** Lifecycle transitions arrive before resumed input, so an input cannot hide a break.
     * Tick runs even without input, but never repaints and never persists. */
    fun activity(next: Runtime) {
        val now=next.at ?: elapsed()
        require(next.lastInput<=now)
        if(runtime==null) previousAt=now
        if(now<previousAt) return // an older captured lifecycle publication cannot rewind time
        val old=runtime
        val oldActive=old!=null && old.visible && !old.sleeping && old.page && !old.modal && !old.presenting && grant==null
        // Gap starts at the idle boundary, or when a lifecycle pause began. Active reading
        // before the five-minute idle limit still counts; at the limit the entire count resets.
        if(oldActive) {
            val idleBoundary=old!!.lastInput+BREAK
            if(now>=idleBoundary) { resetInterval(); gapAt=idleBoundary }
            else activeMs+=(now-previousAt)
        } else if(gapAt==null) gapAt=previousAt
        // Inactivity is one gap across lifecycle boundaries. A short pause must
        // not hide the preceding idle page time when the resume key is fresh.
        if(old!=null && now-old.lastInput>=BREAK) resetInterval()
        if(gapAt?.let {now-it>=BREAK}==true) resetInterval()
        if(grant!=null && (old?.owner!=next.owner || !next.visible || next.sleeping || next.modal ||
            grant!!.due.kind=="interval" && !next.page)) { grant=null; resetInterval() }
        if(old!=null && old.owner!=next.owner) { grant=null; intervalDue=null }
        runtime=next; previousAt=now
        grant?.takeIf {!next.presenting && !drawable(it)}?.let(::retire)
        val active=next.visible && !next.sleeping && next.page && !next.modal && !next.presenting && grant==null && now-next.lastInput<BREAK
        if(active) gapAt=null else if(gapAt==null) gapAt=now
        if(!active && (intervalDue!=null || record(INTERVAL).let {it.enabled && activeMs>=it.intervalMinutes!!*MINUTE})) resetInterval()
        if(waitForInput!=null && next.lastInput>waitForInput!!) waitForInput=null
        val interval=record(INTERVAL)
        if(active && interval.enabled && intervalDue==null && activeMs>=interval.intervalMinutes!!*MINUTE) {
            sequence++
            intervalDue=Due("$session:$sequence",INTERVAL,interval.revision,"interval",session,now,Long.MAX_VALUE,sequence,session)
        }
    }
    private fun timeCandidate(r: Record, now: Long): Due? {
        if(!r.enabled) return null
        val options=mutableListOf<Due>()
        val date=Instant.ofEpochMilli(now).atZone(zone()).toLocalDate()
        for(d in listOf(date.minusDays(1),date)) {
            if(r.days!! and (1 shl (d.dayOfWeek.value-1))==0 || (r.highWater!=null && d.toString()<=r.highWater)) continue
            val due=scheduled(d,r.minuteOfDay!!,zone())
            if(due<=r.after || now-due !in 0..WINDOW) continue
            val original=d.toString()
            options+=Due("${r.id}:$original",r.id,r.revision,"time",original,due,due+WINDOW,missed=now-due>=MINUTE)
        }
        r.snooze?.let { s ->
            val live=snoozeElapsed[r.id]?.takeIf {it.first==s.sequence}
            val late=if(live==null) now-s.due else elapsed()-live.second
            if(late in 0..WINDOW) options+=Due("${r.id}:${s.original}:s${s.sequence}",r.id,r.revision,"time",s.original,
                if(live==null) s.due else now-late,if(live==null) s.due+WINDOW else now-late+WINDOW,s.sequence,missed=late>=MINUTE,elapsedExpiry=live?.second?.plus(WINDOW))
        }
        return options.minWithOrNull(compareBy<Due> {it.due}.thenBy {it.event})
    }
    fun candidates(): List<Due> {
        if(storageUnknown) return emptyList()
        val rt=runtime ?: return emptyList()
        if(!rt.visible || rt.sleeping || grant!=null) return emptyList()
        val times=if(rt.knownClock) state.records.filter {it.kind=="time"}.mapNotNull {timeCandidate(it,wall())}
            .sortedWith(compareBy<Due> {it.due}.thenBy {it.id}) else emptyList()
        if(times.isNotEmpty()) resetInterval()
        if(rt.modal || waitForInput!=null) return emptyList()
        return times.takeIf {it.isNotEmpty()} ?: listOfNotNull(intervalDue?.takeIf {rt.page && elapsed()-rt.lastInput<BREAK})
    }
    fun claim(event: String, owner: String): Grant? {
        val rt=runtime ?: return null
        if(rt.owner!=owner || grant!=null) return null
        val due=candidates().firstOrNull()?.takeIf {it.event==event} ?: return null
        val r=record(due.id)
        if(due.kind=="time") {
            val next=r.copy(highWater=if(due.sequence==0) maxOf(r.highWater ?: "",due.original) else r.highWater,
                snooze=if(due.sequence>0) null else r.snooze)
            persist(state.copy(records=state.records.map {if(it.id==r.id) next else it}))
        } else intervalDue=null
        return Grant(token(),owner,due,elapsed()).also {grant=it; gapAt=elapsed()}
    }
    /** Revalidate on the main-loop draw after the worker returns. Not a new draw grant. */
    fun valid(value: Grant): Boolean {
        val rt=runtime ?: return false
        return grant==value && (rt.presenting || elapsed()-value.issuedAt<=120000) && rt.owner==value.owner && rt.visible && !rt.sleeping && !rt.modal &&
            (value.due.kind=="time" && rt.knownClock || value.due.kind=="interval" && rt.page && (rt.presenting || elapsed()-rt.lastInput<BREAK)) &&
            record(value.due.id).let {it.enabled && it.revision==value.due.revision}
    }
    fun drawable(value: Grant): Boolean = valid(value) && (value.due.kind=="interval" ||
        value.due.elapsedExpiry?.let {elapsed()<=it} ?: (wall()<=value.due.expiry))
    fun retire(value: Grant) {
        if(grant!=value) return
        grant=null;waitForInput=runtime?.lastInput
        if(value.due.kind=="interval") resetInterval()
    }
    fun respond(value: Grant, action: String, sleepAvailable: Boolean = false): Response {
        if(!valid(value) || runtime?.presenting!=true && !drawable(value)) return Response(false)
        val r=record(value.due.id)
        val interval=r.kind=="interval"
        require(action in if(interval) setOf("done","turnOff") else setOf("gotIt","snooze10","sleep"))
        if(action=="sleep" && !sleepAvailable) return Response(false)
        if(action=="sleep" && r.response==value.token) return Response(false)
        if(interval) {
            if(action=="turnOff") setEnabled(r.id,r.revision,false,value.token.take(64))
            resetInterval()
        } else {
            val targetElapsed=elapsed()+10*MINUTE
            val s=if(action=="snooze10") Snooze(value.due.original,wall()+10*MINUTE,value.due.sequence+1) else r.snooze
            val next=r.copy(snooze=s,response=value.token)
            persist(state.copy(records=state.records.map {if(it.id==r.id) next else it}))
            if(action=="snooze10") snoozeElapsed[r.id]=s!!.sequence to targetElapsed
        }
        // Sleep is checkpointed before its one-use native intent. Keep the visible
        // grant until native success, so failure still permits Got it or snooze.
        if(action=="sleep") return Response(true,true)
        grant=null; waitForInput=runtime!!.lastInput; previousAt=elapsed(); gapAt=elapsed()
        return Response(true,action=="sleep")
    }
    fun presentation(r: Record, twelveHour: Boolean, locale: Locale = Locale.getDefault()): Map<String,Any?> {
        val formatter=DateTimeFormatter.ofPattern(if(twelveHour) "h:mm a" else "HH:mm",locale)
            val time=r.minuteOfDay?.let {java.time.LocalTime.of(it/60,it%60).format(formatter)}
            val days=when(r.days) {127->"Every day";31->"Weekdays";96->"Weekends";null->null;else->(0..6).filter {r.days!! and (1 shl it)!=0}.joinToString(", ") {java.time.DayOfWeek.of(it+1).getDisplayName(java.time.format.TextStyle.SHORT,locale)}}
            return mapOf("kind" to r.kind,"id" to r.id,"revision" to r.revision,"source" to "local","sourceLabel" to "This reader",
                "editable" to true,"enabled" to r.enabled,"minuteOfDay" to r.minuteOfDay,"days" to r.days,
                "message" to r.message?.let(LuaValue::str),"intervalMinutes" to r.intervalMinutes,
                "title" to LuaValue.str(if(r.kind=="interval") "Rest your eyes" else time!!),
                "detail" to LuaValue.str(if(r.kind=="interval") "Every ${r.intervalMinutes} minutes of reading" else days!!))
    }
    fun snapshot(twelveHour: Boolean, locale: Locale = Locale.getDefault()): Map<String,Any?> {
        check(storageReady())
        val rows=state.records.map {presentation(it,twelveHour,locale)}
        val result=mapOf("revision" to state.generation,"twelveHour" to twelveHour,"items" to rows,"clockStatus" to if(runtime?.knownClock!=false) "known" else "unknown", "timeLimit" to 8,"timeCount" to state.records.count {it.kind=="time"},"state" to "ready")
        check(LuaValue.encode(result).size<=8192)
        return result
    }
}
