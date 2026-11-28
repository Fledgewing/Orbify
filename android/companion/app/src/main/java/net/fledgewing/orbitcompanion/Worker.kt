package net.fledgewing.orbitcompanion

import android.content.Context
import android.content.Intent
import android.os.Environment
import java.io.File

interface ServerRuntime {
    fun localCommand(ctx: Context, op: String, args: Map<*, *>, done: (Map<String, Any?>?, String?) -> Unit) { done(null,"unsupported") }
    fun accountChanged(ctx: Context)
    fun busy(): Boolean
    val mirrorRunning: Boolean
    fun progressLine(): String?
    fun onIntent(ctx: Context, i: Intent)
    fun nativeFooterRepair(before: String, after: String, token: String)
}

/** One publication satisfies identical requests while it is queued or running. */
internal class PendingBatches {
    private val pending=java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    fun submit(key:String, executor:java.util.concurrent.Executor, work:()->Unit):Boolean {
        if(!pending.add(key)) return false
        try {
            executor.execute { try { work() } finally { pending.remove(key) } }
        } catch(error:RuntimeException) { pending.remove(key);throw error }
        return true
    }
}

/** Command routing only. The selected adapter owns transport and all legacy protocol state. */
object Worker {
    const val ACTION_STORAGE = "${Contract.PACKAGE}.action.STORAGE"
    const val ACTION_SLEEP_REFRESH = "${Contract.PACKAGE}.action.SLEEP_REFRESH"
    const val ACTION_SQLITE_STRESS = "${Contract.PACKAGE}.action.SQLITE_STRESS"
    const val ACTION_PATCH = "${Contract.PACKAGE}.action.PATCH"
    const val CAP = "cache_worker"
    private val deviceBatches=PendingBatches()
    fun localCommand(ctx: Context, op: String, args: Map<*, *>, done: (Map<String, Any?>?, String?) -> Unit) = ServerAdapters.runtime.localCommand(ctx,op,args,done)
    internal fun accountChanged(ctx: Context) = ServerAdapters.runtime.accountChanged(ctx)
    fun root() = File(Environment.getExternalStorageDirectory(), "koreader/settings/orbit-cache")
    fun busy() = ServerAdapters.runtime.busy()
    val mirrorRunning get() = ServerAdapters.runtime.mirrorRunning
    fun progressLine() = ServerAdapters.runtime.progressLine()
    fun onIntent(ctx: Context, i: Intent) {
        if (i.action == ACTION_PATCH && i.getStringExtra("owner") == DeviceLibrary.OWNER && i.hasExtra("library_batch")) {
            val encoded=i.getStringExtra("library_batch")?.takeIf { it.length<=131072 } ?: return
            val app=ctx.applicationContext
            BulkWork.attach(app)
            deviceBatches.submit(encoded,BulkWork.executor) {
                runCatching {
                    val requests=LuaValue.parse(LuaValue.str(encoded).toByteArray(Charsets.ISO_8859_1)) as? List<*> ?: return@runCatching
                    ServerAdapters.projectionStore(root()).use { store ->
                        val model=LibraryReadModel(store, battery={
                            StatsStore.get(app).batterySnapshot(System.currentTimeMillis(),java.time.ZoneId.systemDefault())
                        }, drainEvents={
                            ServerAdapters.runtime.onIntent(app,Intent(ACTION_PATCH).putExtra("drain_events","1"))
                        })
                        model.publish(DeviceLibrary.OWNER,requests)
                    }
                }.onFailure { OLog.w("library.device publication unavailable") }
            }
        } else ServerAdapters.runtime.onIntent(ctx,i)
    }
    internal fun nativeFooterRepair(before: String, after: String, token: String) = ServerAdapters.runtime.nativeFooterRepair(before, after, token)
}
