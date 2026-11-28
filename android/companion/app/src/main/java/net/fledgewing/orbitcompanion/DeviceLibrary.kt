// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

import java.io.File
import java.security.MessageDigest

/** Device files have an identity even before a server is configured. Only the companion
 * scans and parses native sidecars; LibraryReadModel still bounds every published window. */
class DeviceLibrary(
    private val roots: List<File>,
    private val cache: File? = null,
    private val clock: () -> Long = { System.currentTimeMillis()/1000 },
    private val bookStats: (Map<*, *>) -> Map<String, Any?> = { entry ->
        cache?.let { ReaderBookStats.read(it, entry, now=clock()) } ?: mapOf("available" to false)
    },
) : ServerAdapter {
    override val id = "device"
    companion object {
        const val OWNER = "device-local"
        fun metadata(file: File, roots: List<File>): Map<*, *>? {
            val metadata=File(file.parentFile,"${file.nameWithoutExtension}.sdr/metadata.${file.extension}.lua")
            return if(metadata.isFile && metadata.length()<=1048576 && Places.inside(metadata,roots)!=null) runCatching {
                val text=metadata.readText(Charsets.ISO_8859_1).replaceFirst(Regex("\\A(?:--[^\\n]*\\n)?\\s*return\\s+"),"")
                LuaValue.parse(text.toByteArray(Charsets.ISO_8859_1)) as? Map<*,*>
            }.getOrNull() else null
        }
        fun files(roots: List<File>): Sequence<File> = roots.distinctBy { it.canonicalPath }.asSequence().flatMap { root ->
            if (!root.isDirectory) emptySequence() else root.walkTopDown().onEnter {
                BulkWork.checkpoint()
                Places.inside(it,listOf(root)) != null && !java.nio.file.Files.isSymbolicLink(it.toPath()) && !it.name.endsWith(".sdr")
            }.filter { it.isFile && it.extension.lowercase() in setOf("epub","pdf","mobi","azw","azw3","fb2","djvu","cbz","cbr","txt") && Places.inside(it,listOf(root)) != null }
        }.distinctBy { it.canonicalPath }
    }
    private val firstSeen by lazy { DeviceLibraryIndex(cache?.let { File(it,"device-library.properties") },clock) }
    private val covers by lazy { cache?.let { LocalBookCovers(File(it,"local-covers")) } }
    private val books by lazy { files(roots).map { book(it) }.toList().also { firstSeen.rememberSeries(it);firstSeen.flush() } }
    private fun sidecar(file: File) = File(file.parentFile,"${file.nameWithoutExtension}.sdr")
    private fun book(file: File, background: Boolean = true): Map<String,Any?> {
        if(background) BulkWork.checkpoint()
        val metadata=File(sidecar(file),"metadata.${file.extension}.lua")
        val data=metadata(file, roots)
        val props=data?.get("doc_props") as? Map<*,*>
        val summary=data?.get("summary") as? Map<*,*>
        val fraction=(data?.get("percent_finished") as? Number)?.toDouble()?.takeIf { it.isFinite() && it in 0.0..1.0 }
        val status=when(summary?.get("status")) { "complete" -> "finished"; "reading" -> "reading"; "abandoned" -> "abandoned"; else -> if(fraction!=null && fraction>0) "reading" else "unread" }
        val hash=MessageDigest.getInstance("SHA-256").digest(file.canonicalPath.toByteArray()).joinToString("") { "%02x".format(it) }
        val cover=sidecar(file).listFiles()?.filter { it.isFile && it.nameWithoutExtension=="cover" && Places.inside(it,roots)!=null }?.sortedBy { it.name }?.firstOrNull()
        return mapOf("key" to "device:book:$hash","title" to LuaValue.boundedText((props?.get("title") as? String)?.let(LuaValue::utf8) ?: file.nameWithoutExtension,256),
            "series_key" to (props?.get("series") as? String), "series_position" to props?.get("series_index"),
            "authors" to listOfNotNull((props?.get("authors") as? String)?.let { LuaValue.boundedText(LuaValue.utf8(it),256) }),
            "added" to firstSeen.added(file),"md5" to data?.get("partial_md5_checksum"),"local_path" to LuaValue.str(file.canonicalPath),"on_device" to true,"status" to status,"progress" to fraction?.times(100),
            "last_read" to (metadata.lastModified()/1000).takeIf { metadata.isFile },"cover_path" to cover?.path?.let(LuaValue::str),
            "series" to listOfNotNull(props?.get("series")),"series_position" to props?.get("series_index"),
            "formats" to listOf(file.extension.lowercase()),"available" to mapOf("cover" to (cover!=null)),"downloadable" to false)
    }
    override fun personalCatalog(owner: String): Map<String, Any?> =
        if (owner == OWNER) mapOf("items" to books, "freshness" to mapOf("saved" to true)) else unsupported()
    override fun localFiles(owner: String): List<LocalBook>? = if(owner==OWNER) books.map {
        LocalBook(File(LuaValue.utf8(it["local_path"] as String)),it["status"]=="finished",null)
    } else null
    override fun project(owner: String, request: Map<*,*>): Map<String,Any?> {
        if(owner!=OWNER) return mapOf("error" to "unauthorized")
        val fresh=mapOf("saved" to true,"origin" to "local-device")
        fun rows(items: List<*>) = mapOf("items" to items,"freshness" to fresh)
        val op=request["op"]
        if(op=="account.badges") return mapOf("state" to "unavailable","reason" to "Connect an account to save its achievements","row_count" to 1)
        if((request["source"] as? Map<*,*>)?.get("kind")=="finished-year") return unsupported()
        if(request["source"]=="series-next") return unsupported()
        if(op=="capabilities") return mapOf("onDevice" to true,"retainedFinishedYears" to false,"retainedSeriesNext" to false,"readingStats" to true,"catalog" to true,"detail" to true,"download" to false,"libraries" to false,"collections" to false,
            "lists" to mapOf("read" to false,"save" to false),"wantToRead" to false,"progress" to mapOf("read" to true,"write" to false),
            "status" to mapOf("read" to true,"write" to false))
        if(op in setOf("lists","collections")) return rows(emptyList<Any>())
        if(op=="sources") {
            val definitions=listOf(Triple("device","On this device",books.size),Triple("recent","Recently added",books.size),Triple("reading","Reading now",books.count { it["status"]=="reading" }),Triple("finished","All finished",books.count { it["status"]=="finished" }),Triple("pickup","Pick back up",(books.count { it["status"] in setOf("reading","rereading") }-1).coerceAtLeast(0)))
            val offset=((request["offset"] as? Number)?.toInt() ?: 0).coerceAtLeast(0)
            val limit=((request["limit"] as? Number)?.toInt() ?: 6).coerceIn(1,6)
            val category=request["category"] as? String ?: "builtin"
            val available=when(category) {
                "builtin" -> definitions.map { (src,title,count) -> mapOf("src" to src,"title" to title,"count" to count,"default_sort" to 0.takeIf { src=="pickup" }) }+listOf(mapOf("src" to "unopened","title" to "Unopened on this reader","count" to null,"default_sort" to 0))
                "authors","series" -> {
                    val kind=if(category=="authors") "author" else "series"
                    val counts=books.flatMap { book -> (book[if(category=="authors") "authors" else "series"] as? List<*>)?.filterIsInstance<String>().orEmpty().distinct() }.groupingBy { it }.eachCount()
                    counts.keys.sortedWith(String.CASE_INSENSITIVE_ORDER).map { name -> mapOf("src" to "$kind:$name","title" to LuaValue.boundedText(LuaValue.utf8(name),80),"count" to counts[name]) }
                }
                else -> emptyList()
            }
            return rows(available.drop(offset).take(limit))+mapOf("total" to available.size,"next" to (offset+limit).takeIf { it<available.size })
        }
        if(op=="catalog.state") return mapOf("state" to "idle","freshness" to fresh)
        if(op=="library.summary") return mapOf("total" to books.size,"on_device" to books.size,"in_progress" to books.count { it["status"] in setOf("reading","rereading") },
            "browse" to mapOf("complete" to true,"authors" to books.flatMap { (it["authors"] as? List<*>).orEmpty() }.distinct().size,"series" to books.mapNotNull { it["series_key"] }.distinct().size),
            "coverage" to "This reader's files","freshness" to fresh)
        if(op=="series") {
            val key=request["key"] as? String ?: return mapOf("error" to "missing")
            val members=books.filter { it["series_key"]==key }
            if(members.isEmpty()) return mapOf("error" to "missing")
            val offset=((request["offset"] as? Number)?.toInt() ?: 0).coerceAtLeast(0)
            val limit=((request["limit"] as? Number)?.toInt() ?: 12).coerceIn(5,24)
            return SeriesPresentation.series(members,key,offset,limit)+mapOf("freshness" to fresh)
        }
        if(op=="reader.finish") {
            val row=books.firstOrNull { it["local_path"]==request["path"] } ?: return mapOf("error" to "missing")
            val key=row["series_key"]
            val position=(row["series_position"] as? Number)?.toDouble() ?: (row["series_position"] as? String)?.toDoubleOrNull()
            val next=if(key==null || position==null) null else books.filter { it["series_key"]==key && it["key"]!=row["key"] }
                .mapNotNull { candidate ->
                    val number=(candidate["series_position"] as? Number)?.toDouble() ?: (candidate["series_position"] as? String)?.toDoubleOrNull()
                    number?.takeIf { it>position }?.let { it to candidate }
                }.minByOrNull { it.first }?.second
            val finished=row["status"]=="finished"
            return mapOf("key" to row["key"],"title" to row["title"],"author" to (row["authors"] as? List<*>)?.firstOrNull(),
                "series_key" to key,"stars" to request["rating"],"undo" to finished,"can_mark" to !finished,
                "status" to LuaValue.str(if(finished) "✓ Marked as finished" else "Not marked as finished"),
                "next" to next?.let { mapOf("line" to LuaValue.str("Next in series · Book ${it["series_position"]}"),"title" to it["title"],
                    "book_id" to it["key"],"local_path" to it["local_path"],"action" to "open") },
                "row_count" to if(next==null) 1 else 2,"freshness" to fresh)
        }
        if(op in setOf("book","reader","progress","status","cover")) {
            // An explicit in-book panel needs one file, not a library scan waiting for
            // reading to end. All parsing/SQL still stays on the companion worker.
            val row=if(op=="reader") {
                val file=(request["path"] as? String)?.let(LuaValue::utf8)?.let { Places.inside(it,roots) }
                    ?.takeIf { it.isFile } ?: return rows(emptyList<Any>())
                book(file,background=false).also { firstSeen.flush() }
            } else books.firstOrNull { it["key"]==request["key"] } ?: return rows(emptyList<Any>())
            return when(op) {
                "cover" -> mapOf("local_path" to (covers?.cover(File(LuaValue.utf8(row["local_path"] as String)),
                    (row["cover_path"] as? String)?.let { File(LuaValue.utf8(it)) })?.path?.let(LuaValue::str) ?: row["cover_path"]),"freshness" to fresh)
                "progress","status" -> row + mapOf("freshness" to fresh)
                "reader" -> {
                    val current=(request["native_progress"] as? Number)?.toDouble()?.takeIf { it.isFinite() && it in 0.0..1.0 }
                    val enriched=row+mapOf("series_total" to firstSeen.seriesCount(row["series_key"] as? String),"stats" to bookStats(mapOf("md5" to row["md5"],"path" to row["local_path"])))
                    rows(listOf(if(current==null) enriched else enriched+mapOf("progress" to current*100,"progress_origin" to "local-reader")))
                }
                else -> rows(listOf(row+mapOf("stats" to bookStats(mapOf("md5" to row["md5"],"path" to row["local_path"])))))
            }
        }
        if(op !in setOf("window","counts","facets","groups")) return rows(emptyList<Any>())
        val filter=(request["query"] as? Map<*,*>).orEmpty().entries.associate { it.key.toString() to it.value }
        LibraryFilter.validate(filter)
        val source=request["source"]
        val context=source as? Map<*,*>
        val sourceFilter=if(context?.get("kind")=="author") mapOf("author" to listOf(context["key"])) else if(context?.get("kind")=="series") mapOf("series" to listOf(context["key"])) else when(source) { "reading","pick-back-up" -> mapOf("show" to "reading"); "finished" -> mapOf("show" to "finished"); "want-to-read" -> mapOf("wtr" to true); else -> emptyMap() }
        var selected=if(source !in setOf("all","library/all","on-device","reading","pick-back-up","finished","search","recently-added") && context?.get("kind") !in setOf("author","series")) emptyList() else books.filter { LibraryFilter.matches(it,sourceFilter) && LibraryFilter.matches(it,filter) }
        val sort=if(filter["sort"]==null && source in setOf("reading","pick-back-up")) filter+mapOf("sort" to "last","dir" to if(source=="pick-back-up") "asc" else "desc") else if(filter["sort"]==null && source=="recently-added") filter+mapOf("sort" to "added","dir" to "desc") else filter
        selected=selected.sortedWith(LibraryFilter.comparator(sort))
        if((request["exclude_current"]==true || source=="pick-back-up") && source in setOf("reading","pick-back-up")) {
            val current=books.filter { LibraryFilter.matches(it,mapOf("show" to "reading")) }.minWithOrNull(LibraryFilter.comparator(mapOf("sort" to "last","dir" to "desc")))?.get("key")
            selected=selected.filter { it["key"]!=current }
        }
        val offset=((request["offset"] as? Number)?.toInt() ?: 0).coerceAtLeast(0)
        val limit=((request["limit"] as? Number)?.toInt() ?: 24).coerceIn(1,24)
        if(op=="groups") return SeriesPresentation.groups(selected,filter,offset,limit.coerceAtLeast(5),
            ((request["preview"] as? Number)?.toInt() ?: 3).coerceIn(1,9),
            ((request["group_limit"] as? Number)?.toInt() ?: 2).coerceIn(1,6))+mapOf("freshness" to fresh)
        if(op=="counts") return mapOf("total" to selected.size,"freshness" to fresh)
        if(op=="facets") return LibraryFacets(request["field"].toString(),filter,System.currentTimeMillis()/1000).let { facet ->
            selected.forEach { facet.include(it) }; facet.page(offset,limit)+mapOf("freshness" to fresh) }
        return rows(selected.drop(offset).take(limit)) + mapOf("total" to selected.size,"next" to (offset+limit).takeIf { it<selected.size },"local_coverage" to "device-files")
    }
}
