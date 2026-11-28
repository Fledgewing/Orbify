// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

import android.content.Context
import android.content.Intent
import java.io.File
import net.fledgewing.orbitcompanion.server.bookorbit.CatalogTransfers
import net.fledgewing.orbitcompanion.server.bookorbit.RetainedFixture
import net.fledgewing.orbitcompanion.server.bookorbit.SeriesTransfers

/** Compiled only in the disposable emulator build. Never added to app source sets. */
object ServerAdapters {
    private var context: Context? = null
    private val root get() = Worker.root()
    private val deviceSnapshot=ThreadLocal<DeviceLibrary>()
    private fun newBooks()=DeviceLibrary(listOf(File(android.os.Environment.getExternalStorageDirectory(), "Books")), root)
    private val books get() = deviceSnapshot.get() ?: newBooks()
    private fun <T> readBatch(block:()->T):T {
        val previous=deviceSnapshot.get();deviceSnapshot.set(newBooks())
        try { return block() } finally { if(previous==null) deviceSnapshot.remove() else deviceSnapshot.set(previous) }
    }
    private val prefs get() = requireNotNull(context).getSharedPreferences("e2e", Context.MODE_PRIVATE)
    private val signedIn get() = context != null && prefs.getBoolean("signedIn", false)
    private const val OWNER = "emulator-fixture"
    private val transfers by lazy { CatalogTransfers(File(root,"emulator-transfers")) }
    private val seriesTransfers by lazy { SeriesTransfers(File(root,"emulator-transfers"),transfers) }
    private fun perform(owner:String,job:Map<String,Any?>):Map<String,Any?> {
        val id=job["id"] as String
        repeat(20) {
            if(transfers.canceled(owner,id)) throw ServerFailure("canceled")
            transfers.progress(owner,id,(it+1)*1024L,null);Thread.sleep(250)
        }
        val target=File(job["destination"] as String);target.parentFile!!.mkdirs()
        File(android.os.Environment.getExternalStorageDirectory(),"Books/001 Seedfall.epub").copyTo(target,overwrite=true)
        return mapOf("local_path" to target.path)
    }
    private val adapter = object : ServerAdapter {
        override val id = "fixture"
        override fun recommendedSettings()=net.fledgewing.orbitcompanion.server.bookorbit.RecommendedSettings.items
        override fun owner() = OWNER.takeIf { signedIn }
        override fun state(): Map<String, Any?> = mapOf("signedIn" to signedIn, "owner" to owner(), "username" to "reader", "server" to "https://fixture.example.test",
            "account" to mapOf("set" to signedIn, "origin" to "user"),
            "sync" to mapOf("set" to signedIn, "available" to signedIn, "origin" to "account"),
            "opds" to mapOf("set" to signedIn, "available" to signedIn, "origin" to "account"),
            "catalog" to mapOf("canRefresh" to signedIn))
        override fun signIn(server: String, username: String, password: CharArray) {
            try {
                if (server != "https://fixture.example.test" || username != "reader" || String(password) != "fixture") throw ServerFailure("unauthorized")
                prefs.edit().putBoolean("signedIn", true).commit()
            } finally { password.fill('\u0000') }
        }
        override fun signOut() { prefs.edit().putBoolean("signedIn", false).commit() }
        override fun project(owner: String, request: Map<*, *>): Map<String, Any?> {
            HomeFixture.project(books,request)?.let { return it }
            if(request["op"]=="catalog.state") return mapOf("running" to false,"state" to "complete","phase" to "finished","why" to "finished","freshness" to mapOf("saved" to true))
            if(RetainedFixture.handles(request)) return RetainedFixture.project(root,owner,request)
            if(request["op"]=="sources" && (request["category"] ?: "builtin")=="builtin") {
                val options=(books.project(DeviceLibrary.OWNER,mapOf("op" to "sources","category" to "builtin","limit" to 6))["items"] as List<*>).filterNotNull()+RetainedFixture.options(root,owner)
                val offset=(request["offset"] as? Number)?.toInt() ?: 0;val limit=((request["limit"] as? Number)?.toInt() ?: 6).coerceIn(1,6)
                val rows=options.drop(offset).take(limit)
                return mapOf("items" to rows,"total" to options.size,"next" to (offset+rows.size).takeIf { it<options.size },"freshness" to mapOf("saved" to true))
            }
            if(request["op"]=="capabilities") return books.capabilities(DeviceLibrary.OWNER)+mapOf("retainedFinishedYears" to true,"retainedSeriesNext" to true,"series" to mapOf("read" to true,"downloadNext" to true),"download" to true,"lists" to mapOf("read" to true,"save" to false))
            if(request["op"]=="lists") return mapOf("items" to listOf(mapOf("key" to "fixture-list","title" to "Fixture shelf","count" to 59)),"freshness" to mapOf("saved" to true))
            return books.project(DeviceLibrary.OWNER, request)
        }
        override fun personalCatalog(owner: String) = books.personalCatalog(DeviceLibrary.OWNER)
        override fun localFiles(owner: String) = books.localFiles(DeviceLibrary.OWNER)
        override fun catalogControl(owner: String, action: String, manual: Boolean, done: (Map<String, Any?>?, String?) -> Unit) {
            val scope=owner()
            if(scope==null) { done(null,"unauthorized");return }
            BulkWork.executor.execute {
                try {
                    if(owner()!=scope) throw ServerFailure("canceled")
                    projectionStore(root).use { store ->
                        store.db().exec("INSERT OR REPLACE INTO meta(k,v) VALUES ('owner',?)",scope)
                        val request=String(LuaValue.encode(mapOf("op" to "catalog.state","limit" to 1L,"bytes" to 16384L)),Charsets.ISO_8859_1)
                        LibraryReadModel(store,adapter=this).publish(scope,listOf(request))
                    }
                    done(mapOf("state" to "complete","freshness" to mapOf("saved" to true)),null);event()
                } catch(e:Exception) { done(null,if(e is ServerFailure) e.kind else "unavailable") }
            }
        }
        override fun catalogAction(owner:String,action:String,args:Map<*,*>,done:(Map<String,Any?>?,String?)->Unit) {
            try {
                when(action) {
                    "series.preview" -> {
                        val count=(args["count"] as? Number)?.toInt() ?: 3
                        done(mapOf("items" to (1..count).map { mapOf("key" to "series-review-$it","title" to "Series review $it","number" to it) },"token" to "fixture-series-$count","row_count" to count+1),null)
                    }
                    "series.find" -> done(seriesTransfers.find(owner,args["key"] as String) ?: mapOf("row_count" to 1),null)
                    "series.status" -> done(seriesTransfers.read(owner,args["id"] as String),null)
                    "series.cancel" -> done(seriesTransfers.cancel(owner,args["id"] as String),null)
                    "series.start","series.resume" -> {
                        val count=(args["count"] as? Number)?.toInt() ?: 3
                        val result=if(action=="series.resume") seriesTransfers.resume(owner,args["id"] as String) else seriesTransfers.start(owner,args["key"] as String,
                            (1..count).map { mapOf("key" to "series-review-$it","title" to "Series review $it","file_reference" to 1L,"destination" to "/storage/emulated/0/BookSync/Series review $it.epub") })
                        done(result,null)
                        BulkWork.executor.execute { seriesTransfers.run(owner,result["id"] as String) { perform(owner,it) } }
                    }
                    "download.prepare" -> done(mapOf("items" to listOf(
                        mapOf("file_reference" to 1L,"label" to "EPUB","destination" to "/storage/emulated/0/BookSync/Transfer review.epub"),
                        mapOf("file_reference" to 2L,"label" to "PDF","destination" to "/storage/emulated/0/BookSync/Transfer review.pdf")),"row_count" to 2),null)
                    "download.status" -> done(transfers.read(owner,args["id"] as String),null)
                    "download.cancel" -> done(transfers.cancel(owner,args["id"] as String),null)
                    "download.start","download.resume" -> {
                        val result=if(action=="download.start") transfers.start(owner,args) else transfers.resume(owner,args["id"] as String)
                        done(result,null)
                        BulkWork.executor.execute { transfers.run(owner,result["id"] as String) { perform(owner,it) } }
                    }
                    else -> done(null,"unsupported")
                }
            } catch(e:ServerFailure) { done(null,e.kind) }
        }
        override fun captureLifecycle(capture: Map<*, *>): Pair<String, ByteArray> =
            ("fixture-document-" + java.security.MessageDigest.getInstance("SHA-256").digest((capture["path"] as? String ?: "fixture").toByteArray()).joinToString("") { "%02x".format(it) }) to LuaValue.encode(mapOf("percentage" to capture["percentage"], "position" to capture["position"], "capturedAt" to System.currentTimeMillis()/1000))
        override fun position(document: String, update: Map<String, Any?>?): Map<String, Any?> {
            val file=File(requireNotNull(context).filesDir,"e2e-position.lua")
            if(update!=null) {
                file.writeBytes(LuaValue.encode(update))
                return update
            }
            // A scripted second reader stays ahead throughout this scenario. Local
            // background uploads are recorded separately and cannot replace its place.
            return mapOf("percentage" to 0.5,"label" to "Fixture tablet","timestamp" to 1_700_000_000L)
        }
        override fun lifecyclePhase(entry: LifecycleQueue.Entry, phase: String, checkpoint: ByteArray, openPath: String?) = SyncPhaseResult(checkpoint)
    }
    fun session(ctx: Context, id: String = "fixture"): ServerAdapter { context=ctx.applicationContext; return adapter }
    fun forStore(store: ProjectionStore, id: String = "fixture", clock: () -> Long = { System.currentTimeMillis()/1000 },
        fallbackReadingStats: ((String) -> RemoteReadingStats?)? = null,
        accountState: () -> Map<String, Any?> = { emptyMap() }, accountStats: (String) -> Map<*, *>? = { null }): ServerAdapter = adapter
    fun projectionStore(root: File) = ShippingServerAdapters.projectionStore(root)
    val connector get() = ShippingServerAdapters.connector
    val cachedLists get() = ShippingServerAdapters.cachedLists
    val covers get() = ShippingServerAdapters.covers
    val runtime = object : ServerRuntime {
        override fun localCommand(ctx:Context,op:String,args:Map<*,*>,done:(Map<String,Any?>?,String?)->Unit) {
            context=ctx.applicationContext
            BulkWork.executor.execute {
                try {
                    val owner=args["owner"] as? String ?: throw ServerFailure("unauthorized")
                    if(owner!=(LibraryAccount.owner() ?: DeviceLibrary.OWNER)) throw ServerFailure("canceled")
                    val result=projectionStore(root).use { store -> LibraryReadModel(store,adapter=adapter).storageCommand(owner,op,args) }
                    done(result,null);event()
                } catch(_:Exception) { done(null,"unavailable") }
            }
        }
        override fun accountChanged(ctx: Context) {
            context=ctx.applicationContext
            BulkWork.executor.execute {
                projectionStore(root).use { store ->
                    store.db().exec("INSERT OR REPLACE INTO meta(k,v) VALUES ('owner',?)", OWNER)
                }
                event()
            }
        }
        override fun busy() = false
        override val mirrorRunning = false
        override fun progressLine(): String? = null
        override fun nativeFooterRepair(before: String, after: String, token: String) {}
        override fun onIntent(ctx: Context, i: Intent) {
            context=ctx.applicationContext
            if(i.getStringExtra("drain_events")=="1") {
                val ack=i.getStringExtra("events_ack")
                BulkWork.executor.execute { EventMailbox(root).publish(ack) }
                return
            }
            val raw=i.getStringExtra("library_batch") ?: return
            val owner=i.getStringExtra("owner") ?: return
            BulkWork.executor.execute {
                runCatching {
                    val requests=LuaValue.parse(LuaValue.str(raw).toByteArray(Charsets.ISO_8859_1)) as List<*>
                    projectionStore(root).use { store ->
                        store.db().exec("INSERT OR REPLACE INTO meta(k,v) VALUES ('owner',?)", OWNER)
                        readBatch { LibraryReadModel(store, adapter=adapter).publish(owner,requests) }
                    }
                    event()
                }.onFailure { OLog.w("emulator fixture projection failed",it) }
            }
        }
    }
    private fun event() {
        val spool=File(root,"events").also { it.mkdirs() }
        val file=File(spool,"fixture-${java.util.UUID.randomUUID()}.lua")
        val temp=File(spool,file.name+".part")
        temp.writeBytes(LuaValue.encode(mapOf("kind" to "library","owner" to OWNER)))
        check(temp.renameTo(file));EventMailbox(root).publish(null)
    }
}
