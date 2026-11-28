package net.fledgewing.orbitcompanion

import android.content.Context
import android.os.SystemClock
import java.io.File

/** Trusted-provider commands: inputs/results are neutral and bounded; typed secrets are transient inputs, never results or retained jobs. */
object ServerCommands {
    const val START = "${Contract.PACKAGE}.call.SERVER_COMMAND"
    const val RESULT = "${Contract.PACKAGE}.call.SERVER_RESULT"
    private class Pending(val at: Long, var body: Map<String,Any?>? = null)
    private val jobs = linkedMapOf<String,Pending>()
    @Synchronized fun start(ctx: Context, op: String, args: Map<*, *>): String {
        require(op in setOf("reader.companion","reminders.draft","reminders.list","reminders.retry","reminders.runtime","reminders.add","reminders.edit","reminders.setEnabled","reminders.delete","reminders.claimDue","reminders.respond","reminders.sleep","reading.local.read","reading.local.goal","reading.local.event","reading.local.prepare","device.sleep","storage.free","storage.folder","storage.refresh","storage.remove.preview","storage.remove","sync.verify.next","sync.verify.result","sync.activate","sync.capture","sync.pull","sync.decide","sync.answer","sync.override","sync.drain","sync.read","sync.write","catalog.window","catalog.control","catalog.action","settings.recommendations","covers.acquire","downloads.start","account.signIn","account.signOut","login.save","login.remove","login.replace"))
        val now = SystemClock.elapsedRealtime()
        jobs.entries.removeAll { now - it.value.at > 120000 }
        require(jobs.size < 32)
        val id = java.util.UUID.randomUUID().toString()
        jobs[id] = Pending(now)
        fun finish(result: Map<String,Any?>?, error: String?) = synchronized(this) {
            val body = if (error != null) mapOf("error" to error) else result ?: mapOf("ok" to true)
            jobs[id]?.body = if (LuaValue.encode(body).size <= 16384) body else mapOf("error" to "budget")
        }
        fun accountDone(error: String?) = finish(mapOf("state" to LibraryAccount.state()),error)
        fun text(key: String) = LuaValue.utf8(args[key] as? String ?: throw IllegalArgumentException("missing"))
        try { when (op) {
            "reminders.draft","reminders.list","reminders.retry","reminders.runtime","reminders.add","reminders.edit","reminders.setEnabled","reminders.delete","reminders.claimDue","reminders.respond","reminders.sleep" -> LibraryReminders.command(ctx,op,args,::finish)
            "reading.local.read","reading.local.goal","reading.local.event","reading.local.prepare" -> LibraryLocalReading.command(op,args,::finish)
            "sync.verify.next","sync.verify.result","sync.activate","sync.capture","sync.pull","sync.decide","sync.answer","sync.override","sync.drain" -> LibraryAccount.sync(ctx,op,args,::finish)
            "storage.free", "storage.folder", "storage.refresh", "storage.remove.preview", "storage.remove" -> Worker.localCommand(ctx,op,args,::finish)
            "reader.companion" -> ReaderCompanion.command(ctx,args,::finish)
            "device.sleep" -> DeviceSettings.sleep(ctx,(args["ms"] as? Number)?.toInt() ?: 600000) { finish(mapOf("device" to DeviceSettings.snapshot()),it) }

            "account.signIn" -> LibraryAccount.signIn(ctx,text("server"),text("username"),text("password").toCharArray(),::accountDone)
            "account.signOut" -> LibraryAccount.signOut(ctx,::accountDone)
            "login.save" -> LibraryAccount.setLogin(ctx,text("kind"),text("server"),text("username"),text("password").toCharArray(),false,::accountDone)
            "login.remove" -> LibraryAccount.removeLogin(ctx,text("kind"),::accountDone)
            "login.replace" -> LibraryAccount.useAccountLogin(ctx,text("kind"),::accountDone)
            "sync.read", "sync.write" -> {
                val document = args["document"] as? String ?: throw IllegalArgumentException("document")
                val update = if (op == "sync.write") mapOf("percentage" to args["percentage"], "position" to args["position"]) else null
                LibraryAccount.position(ctx,document,update,::finish)
            }
            "catalog.window" -> LibraryAccount.catalog(ctx,(args["page"] as? Number)?.toInt() ?: 1,(args["limit"] as? Number)?.toInt()?.coerceIn(1,24) ?: 24,::finish)
            "settings.recommendations" -> LibraryAccount.recommendedSettings(ctx,args,::finish)
            "catalog.action" -> LibraryAccount.catalogAction(ctx,args["owner"] as? String ?: throw IllegalArgumentException("owner"),text("action"),args,::finish)
            "catalog.control" -> LibraryAccount.catalogControl(ctx,args["owner"] as? String ?: throw IllegalArgumentException("owner"),text("action"),args["manual"]==true,::finish)
            "covers.acquire" -> if (args["reference"] != null)
                LibraryAccount.acquireCoverReference(ctx,text("reference"),args["refresh"]==true,args["owner"] as? String ?: throw IllegalArgumentException("owner"),::finish)
                else if (text("key").startsWith("device:book:")) Worker.localCommand(ctx,op,args,::finish)
                else LibraryAccount.acquireCover(ctx,text("key"),::finish)
            "downloads.start" -> {
                val key = args["key"] as? String ?: throw IllegalArgumentException("key")
                val destination = File(LuaValue.utf8(args["destination"] as? String ?: throw IllegalArgumentException("destination")))
                LibraryAccount.download(ctx,key,destination) { finish(mapOf("local_path" to LuaValue.str(destination.path)),it) }
            }
        } } catch (e: Exception) { jobs.remove(id); throw e }
        return id
    }
    @Synchronized fun result(id: String): Map<String,Any?> {
        val job = jobs[id] ?: return mapOf("error" to "missing")
        val body = job.body ?: return mapOf("pending" to true)
        jobs.remove(id)
        return body
    }
}
