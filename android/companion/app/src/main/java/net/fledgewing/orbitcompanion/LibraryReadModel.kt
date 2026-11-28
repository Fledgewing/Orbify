package net.fledgewing.orbitcompanion

/** Worker-owned projections in the existing cache DB. Plugin reads one small blob per operation.
 * Additive table: no schema reset, no second catalog, sync writer, credentials or network client. */
class LibraryReadModel(
    private val store: ProjectionStore,
    private val clock: () -> Long = { System.currentTimeMillis() / 1000 },
    private val log: (String) -> Unit = { OLog.i(it) },
    private val readingStats: (() -> Map<String, Any?>)? = null,
    private val battery: () -> Map<String, Any?> = { BatteryEstimate.snapshot(emptyMap(), emptyList(), null, emptyList(), clock()*1000, java.time.ZoneOffset.UTC) },
    private val fallbackReadingStats: ((String) -> RemoteReadingStats?)? = null,
    private val accountState: () -> Map<String, Any?> = LibraryAccount::state,
    private val accountStats: (String) -> Map<*, *>? = LibraryAccount::stats,
    private val vocabulary: () -> java.io.File = { java.io.File(SleepScreen.dir().parentFile, "vocabulary_builder.sqlite3") },
    private val adapter: ServerAdapter? = null,
    private val personalDevice: (() -> PersonalReadingSource)? = null,
    private val sleepChoices: () -> SleepChoices? = { SleepChoices.read(SleepScreen.dir()) },
    // Device publication schedules draining on the existing runtime writer queue.
    private val drainEvents: () -> Unit = { EventMailbox(store.root).publish(null) },
    private val changedEvent: (Map<String, Any?>) -> Unit = { event ->
        val file = java.io.File(store.root, "events/library-${java.util.UUID.randomUUID()}.lua")
        file.parentFile?.mkdirs()
        val temp = java.io.File(file.parentFile, file.name + ".part")
        try { temp.writeBytes(LuaValue.encode(event)); check(temp.renameTo(file)) }
        finally { temp.delete() }
        drainEvents()
    },
) {
    companion object {
        const val MAX_BYTES = 16384
        const val MAX_ROWS = 24
        const val MAX_BATCH = 16
        fun initialize(db: Sql) = db.exec("CREATE TABLE IF NOT EXISTS library_views (owner TEXT, request TEXT, body BLOB, at INTEGER, PRIMARY KEY(owner,request)) WITHOUT ROWID")
    }
    /** Each request is its exact Lua literal: no hash collision or backend URL in the UI key. */
    fun publish(owner: String, requests: List<*>): Boolean = publishBatch(owner, requests).also {
        if (it) notifyChanged(owner)
    }

    private fun notifyChanged(owner: String) {
        if (owner != DeviceLibrary.OWNER && store.meta("owner") != owner) return
        changedEvent(mapOf("kind" to "library", "owner" to owner))
    }

    private fun publishBatch(owner: String, requests: List<*>): Boolean {
        var changed = false
        require(requests.size <= MAX_BATCH)
        // Never take ownership from a read command, nor expose a prior account's data.
        if (owner != DeviceLibrary.OWNER && store.meta("owner") != owner) return false
        val local = owner == DeviceLibrary.OWNER
        val projection = if (local) DeviceLibrary(roots(),store.root,clock) else adapter ?: ServerAdapters.forStore(store, clock = clock,
            fallbackReadingStats = fallbackReadingStats, accountState = accountState, accountStats = accountStats)
        val personal by lazy {
            val roots = roots()
            PersonalReading(listOf(personalDevice?.invoke() ?: DevicePersonalReading(roots, java.io.File(store.root.parentFile,"statistics.sqlite3"))) +
                if (local) emptyList() else listOf(CatalogPersonalReading { projection.personalCatalog(owner) }) + projection.personalReadingSources(owner))
        }
        val account by lazy { if (local) null else accountStats(owner) }
        val localStats by lazy { readingStats?.invoke() ?: ReadingStats.read(
            java.io.File(store.root.parentFile, "statistics.sqlite3"), clock(),
            if (local) java.time.ZoneId.systemDefault() else AccountStats.zone(account)) }
        val unopened by lazy { UnopenedLibrary(roots(),store.root.parentFile?.parentFile ?: store.root,clock()) }
        val localCompletion by lazy { LibraryLocalReading.snapshot(store.root.parentFile!!) }
        val storage by lazy { DeviceStorage(store, projection) }
        val power by lazy { battery() }
        val stats by lazy { ReadingStats.display(AccountStats.combine(ReadingStats.withLocalCompletion(localStats, localCompletion), if (local) null else projection.cachedReadingStats(owner), account, clock()), clock(), AccountStats.zone(account)) }
        for (encoded in requests) {
            val start = System.nanoTime()
            val request = encoded as? String ?: continue
            if (request.length > 8192) continue
            val args = LuaValue.parse(request.toByteArray(Charsets.ISO_8859_1)) as? Map<*, *> ?: continue
            // Native folder/history work may pause for reading. Never hold a cache
            // transaction while that checkpoint waits for the foreground book.
            val localUnopened=try { if(local || store.meta("owner")==owner) when {
                args["op"]=="local.dust" -> unopened.dust(args)
                args["op"] in setOf("window","counts","facets","groups") && args["source"]=="unopened" -> unopened.window(args)
                else -> null
            } else null } catch (_:IllegalArgumentException) { mapOf("error" to "unsupported","items" to emptyList<Any>()) }
            store.transaction {
                if (!local && store.meta("owner") != owner) return@transaction
                val projected = try { when {
                    localUnopened!=null -> localUnopened
                    else -> when (args["op"]) {
                    "storage.summary" -> storage.summary(owner,(args["exclude_path"] as? String)?.let(LuaValue::utf8),(args["current_folder"] as? String)?.let(LuaValue::utf8))
                    "reader.controls" -> ReaderControls.read(args["native"] as? Map<*, *> ?: emptyMap<Any, Any>(),java.io.File(store.root.parentFile,"statistics.sqlite3"),clock())

                    "personal.reading" -> personal.window(args["kind"] as? String ?: "", clock(), (args["pick"] as? Number)?.toLong() ?: 0)
                    "reading.local" -> localCompletion
                    "reading.stats" -> stats
                    "reading.metrics" -> RetainedMetrics.snapshot(stats,clock(),AccountStats.zone(account))
                    "local.moon","local.glyph" -> LocalDecor.snapshot(args["op"].toString().removePrefix("local."),clock())
                    "local.nextstop" -> NextStop.read(args["native"] as? Map<*,*> ?: emptyMap<Any,Any>(),java.io.File(store.root.parentFile,"statistics.sqlite3"),clock())
                    "local.controls" -> LocalWidgets.controls(args["native"] as? Map<*,*> ?: emptyMap<Any,Any>(),clock())
                    "local.word" -> LocalWidgets.word(vocabulary(), clock())
                    "local.buddy" -> LocalWidgets.buddy(localStats)
                    "local.light" -> LocalWidgets.light(args["native"] as? Map<*, *> ?: emptyMap<Any, Any>())
                    "device.clock" -> ClockWidget.snapshot(clock(), power, twelve = args["twelve_hour"] == true)
                    "mode-estimates" -> BatteryEstimate.modeRows(power, (args["limit"] as? Number)?.toInt() ?: 3)
                    "battery" -> power
                    "sleep.choices" -> SleepChoiceWindow.project(sleepChoices(), args)
                    "capabilities" -> projection.capabilities(owner) + mapOf("battery" to true,"removeDownload" to true)
                    else -> projection.project(owner, args)
                } } } catch (_: IllegalArgumentException) { mapOf("error" to "unsupported", "items" to emptyList<Any>()) }
                // Enrich only the bounded display window, never the full catalog. Saved covers
                // and personal pace share its row/byte budget and its single Home batch.
                val result = if (args["op"] == "window" && args["source"]!="unopened") {
                    val seconds = ((localStats["year"] as? Map<*, *>)?.get("seconds") as? List<*>).orEmpty()
                    val daily = seconds.takeLast(14).sumOf { (it as? Number)?.toLong() ?: 0 } / 14
                    projected + mapOf("items" to (projected["items"] as? List<*>).orEmpty().map { raw ->
                        @Suppress("UNCHECKED_CAST") val row = raw as Map<String, Any?>
                        val key = row["key"] as? String
                        val cover = (if (key == null) null else projection.project(owner, mapOf("op" to "cover", "key" to key))["local_path"]) ?: row["cover_path"]
                        val enriched = personal.card(row, clock(), daily)
                        val series = (row["series"] as? List<*>)?.firstOrNull() as? String
                        enriched + mapOf("cover_path" to cover,
                            "available" to ((row["available"] as? Map<*, *>).orEmpty() + mapOf("cover" to (cover != null))),
                            "series_line" to series?.let { name -> LuaValue.str(LuaValue.utf8(name) + (row["series_position"]?.let { " · Book $it" } ?: "")) },
                            "time_left" to (enriched["time_left"] ?: "Not enough reading yet"),
                            "finish_forecast" to (enriched["finish_forecast"] ?: "Finish date unavailable"))
                    })
                } else projected
                val items = result["items"] as? List<*>
                val measuredRows = (items?.size ?: 1) + items.orEmpty().sumOf {
                    ((it as? Map<*, *>)?.get("books") as? List<*>)?.size ?: 0
                } + ((result["next_books"] as? List<*>)?.size ?: 0) +
                    (if (args["op"] == "series" && result.containsKey("subtitle")) 1 else 0)
                val rows = maxOf(measuredRows, (result["row_count"] as? Number)?.toInt() ?: 0)
                val boundedResult = if (result.containsKey("row_count")) result + mapOf("row_count" to rows) else result
                var body = LuaValue.encode(boundedResult)
                val budget = ((args["bytes"] as? Number)?.toInt() ?: MAX_BYTES).coerceIn(256, MAX_BYTES)
                val rowBudget = ((args["limit"] as? Number)?.toInt() ?: MAX_ROWS).coerceIn(1, MAX_ROWS)
                if (body.size > budget || rows > rowBudget) body = LuaValue.encode(mapOf(
                    "error" to "budget", "items" to emptyList<Any>(), "freshness" to mapOf("saved" to false)))
                val previous = store.db().query("SELECT body FROM library_views WHERE owner=? AND request=?", LuaValue.utf8(owner), LuaValue.utf8(request)) { it.bytes(0) }.firstOrNull()
                if (previous == null || !previous.contentEquals(body)) changed = true
                store.db().exec("INSERT OR REPLACE INTO library_views VALUES (?,?,?,?)", LuaValue.utf8(owner), LuaValue.utf8(request), body, clock())
                // Bounded projection cache; catalog and reading intents are untouched.
                store.db().exec("DELETE FROM library_views WHERE (owner,request) IN (SELECT owner,request FROM library_views ORDER BY at DESC,request LIMIT -1 OFFSET 64)")
                log("library ${args["op"]} ms=${(System.nanoTime()-start)/1_000_000} rows=$rows bytes=${body.size}")
            }
        }
        return changed
    }
    /** Rebuild only retained windows affected by this lifecycle, then signal once after writes. */
    private fun refresh(owner: String, operations: Set<String>): Boolean {
        if (owner != DeviceLibrary.OWNER && store.meta("owner") != owner) return false
        val requests = store.db().query("SELECT request FROM library_views WHERE owner=? LIMIT 64", LuaValue.utf8(owner)) { LuaValue.str(it.text(0)!!) }
            .filter { raw -> (LuaValue.parse(raw.toByteArray(Charsets.ISO_8859_1)) as? Map<*, *>)?.get("op") in operations }
        var changed = false
        requests.chunked(MAX_BATCH).forEach { if (publishBatch(owner, it)) changed = true }
        // Commands can change state outside retained windows; preserve their invalidation event.
        notifyChanged(owner)
        return changed
    }

    fun refreshReadingIntents(owner: String): Boolean = refresh(owner, setOf("reader.finish", "copies.state"))

    /** Removal changes file joins for both catalog and device windows; battery stays retained. */
    fun refreshLocalFiles(owner: String): Boolean = refresh(owner, setOf(
        "storage.summary", "library.summary", "window", "book", "reader", "reader.finish", "cover", "cover.reference",
        "groups", "series", "counts", "facets", "sources", "personal.reading"))

    fun storageCommand(owner: String, op: String, args: Map<*, *>): Map<String, Any?> {
        val projection = if (owner == DeviceLibrary.OWNER) DeviceLibrary(roots(),store.root,clock) else adapter ?: ServerAdapters.forStore(
            store, clock = clock, fallbackReadingStats = fallbackReadingStats, accountState = accountState, accountStats = accountStats)
        if(op=="covers.acquire") return projection.project(owner,mapOf("op" to "cover","key" to args["key"]))
        val result = if(op=="storage.refresh") mapOf("ok" to true) else DeviceStorage(store, projection).command(owner, op, args)
        if(op=="storage.remove.preview") return result
        // Local files are shared, but each owner is projected independently with fresh batch context.
        refreshLocalFiles(owner)
        val other = if (owner == DeviceLibrary.OWNER) store.meta("owner") else DeviceLibrary.OWNER
        if (other != null && other != owner) refreshLocalFiles(other)
        return result
    }

    private fun roots() = DeviceStorage.folders.map {
        java.io.File(store.root.parentFile?.parentFile?.parentFile ?: store.root, it)
    } + DeviceStorage.downloadRoot(store.root)
}
