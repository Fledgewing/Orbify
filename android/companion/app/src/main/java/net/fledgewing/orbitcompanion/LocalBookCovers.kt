// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Looper
import android.os.ParcelFileDescriptor
import java.io.File
import java.net.URI
import java.security.MessageDigest
import java.util.zip.ZipFile
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Document
import org.w3c.dom.Element

/** Worker-only extraction. KOReader's document providers cannot be invoked across processes;
 * PDF uses Android's first-page renderer and CBZ uses its first image. No reader UI work.
 * Cache variants fit the shelf, book row and hero/detail cover boxes without stretching. */
class LocalBookCovers(private val directory: File, private val firstPdfPage: ((File) -> Bitmap?)? = null) {
    companion object {
        val sizes = listOf(160 to 240, 320 to 480, 600 to 900)
        private const val MAX_IMAGE = 20*1024*1024
        private const val MAX_XML = 1024*1024
    }
    fun cover(book: File, sidecar: File? = null, size: Pair<Int,Int> = sizes.last()): File? {
        if(runCatching { Looper.getMainLooper()?.let { it == Looper.myLooper() } }.getOrNull()==true) return null
        require(size in sizes)
        BulkWork.checkpoint()
        val signature="${book.canonicalPath}:${book.length()}:${book.lastModified()}:${sidecar?.length()}:${sidecar?.lastModified()}"
        fun hash(value: String)=MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") { "%02x".format(it) }
        val prefix=hash(book.canonicalPath)+"-"
        val generation=prefix+hash(signature)
        val target=File(directory,"$generation-${size.first}x${size.second}.jpg")
        if(target.isFile) return target
        return runCatching {
            NoMedia.directory(directory)
            val source=sidecar?.takeIf { it.length() in 1..MAX_IMAGE }?.readBytes()?.let(::decode)
                ?: when(book.extension.lowercase()) {
                    "pdf" -> firstPdfPage?.invoke(book) ?: pdf(book)
                    "epub","cbz" -> embedded(book)?.let(::decode)
                    else -> null
                } ?: return null
            try {
                for((width,height) in sizes) {
                    BulkWork.checkpoint()
                    val dest=File(directory,"$generation-${width}x$height.jpg")
                    if(dest.isFile) continue
                    val scale=minOf(1.0,width.toDouble()/source.width,height.toDouble()/source.height)
                    val thumbnail=Bitmap.createScaledBitmap(source,maxOf(1,(source.width*scale).toInt()),maxOf(1,(source.height*scale).toInt()),true)
                    val temp=File.createTempFile("cover-",".part",directory)
                    try {
                        check(temp.outputStream().use { thumbnail.compress(Bitmap.CompressFormat.JPEG,85,it) })
                        check(temp.length() in 1..524288)
                        check(temp.renameTo(dest))
                    } finally { temp.delete(); if(thumbnail!==source) thumbnail.recycle() }
                }
                // Keep only this book's current generation; no changes to native sidecars.
                directory.listFiles()?.filter { it.name.startsWith(prefix) && !it.name.startsWith(generation) }?.forEach { it.delete() }
                target
            } finally { source.recycle() }
        }.getOrNull()
    }
    private fun decode(bytes: ByteArray): Bitmap? {
        val bounds=BitmapFactory.Options().apply { inJustDecodeBounds=true }
        BitmapFactory.decodeByteArray(bytes,0,bytes.size,bounds)
        if(bounds.outWidth<=0 || bounds.outHeight<=0) return null
        return BitmapFactory.decodeByteArray(bytes,0,bytes.size,BitmapFactory.Options().apply {
            inSampleSize=SharpCoversLogic.sample(bounds.outWidth,bounds.outHeight,600,900)
        })
    }
    private fun pdf(book: File): Bitmap? = ParcelFileDescriptor.open(book,ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
        PdfRenderer(descriptor).use { renderer ->
            if(renderer.pageCount==0) return null
            renderer.openPage(0).use { page ->
                val scale=minOf(600.0/page.width,900.0/page.height)
                val image=Bitmap.createBitmap(maxOf(1,(page.width*scale).toInt()),maxOf(1,(page.height*scale).toInt()),Bitmap.Config.ARGB_8888)
                image.eraseColor(Color.WHITE)
                try { page.render(image,null,null,PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY); image }
                catch(e: Exception) { image.recycle(); throw e }
            }
        }
    }
    /** Bounded ZIP reads, package-relative paths only, no external XML entities or extraction to disk. */
    internal fun embedded(book: File): ByteArray? = ZipFile(book).use { zip ->
        fun bytes(path: String, max: Int): ByteArray? {
            val entry=zip.getEntry(path)?.takeUnless { it.isDirectory || it.size>max } ?: return null
            return zip.getInputStream(entry).use { input ->
                val output=java.io.ByteArrayOutputStream()
                val buffer=ByteArray(8192)
                var count=input.read(buffer)
                while(count!=-1) {
                    if(output.size()+count>max) return null
                    output.write(buffer,0,count)
                    count=input.read(buffer)
                }
                output.toByteArray()
            }
        }
        fun xml(path: String): Document? = bytes(path,MAX_XML)?.let { data ->
            // Android's parser does not implement Xerces' disallow-doctype feature.
            // Parse a decoded character stream so a declared encoding cannot hide a DTD
            // from this check. EPUB package documents are UTF-8 or BOM-marked UTF-16.
            val charset=if(data.size>=2 && (data[0]==0xff.toByte() && data[1]==0xfe.toByte() ||
                data[0]==0xfe.toByte() && data[1]==0xff.toByte())) Charsets.UTF_16 else Charsets.UTF_8
            val text=data.toString(charset)
            require(!Regex("<!\\s*(DOCTYPE|ENTITY)",RegexOption.IGNORE_CASE).containsMatchIn(text))
            val factory=DocumentBuilderFactory.newInstance().apply { isNamespaceAware=true }
            val builder=factory.newDocumentBuilder()
            builder.setEntityResolver { _,_ -> throw org.xml.sax.SAXException("External entities are disabled") }
            builder.parse(org.xml.sax.InputSource(java.io.StringReader(text)))
        }
        fun Document.elements(name: String): List<Element> = getElementsByTagNameNS("*",name).let { list -> (0 until list.length).map { list.item(it) as Element } }
        fun resolve(base: String, href: String): String? = runCatching {
            val resolved=URI("/$base").resolve(href).normalize()
            resolved.path.removePrefix("/").takeIf { resolved.scheme==null && resolved.authority==null && !it.startsWith("../") }
        }.getOrNull()
        if(book.extension.equals("cbz",true)) {
            val entry=zip.entries().asSequence().filter { !it.isDirectory && it.name.substringAfterLast('.').lowercase() in setOf("jpg","jpeg","png","webp") }
                .sortedBy { Regex("\\d+").replace(it.name.lowercase()) { n -> n.value.padStart(12,'0') } }.firstOrNull()
            return entry?.let { bytes(it.name,MAX_IMAGE) }
        }
        val packagePath=xml("META-INF/container.xml")?.elements("rootfile")?.firstOrNull()?.getAttribute("full-path") ?: return null
        val opf=xml(packagePath) ?: return null
        val items=opf.elements("item")
        val coverId=opf.elements("meta").firstOrNull { it.getAttribute("name")=="cover" }?.getAttribute("content")
        val explicit=items.firstOrNull { "cover-image" in it.getAttribute("properties").split(Regex("\\s+")) }
            ?: items.firstOrNull { coverId!=null && it.getAttribute("id")==coverId }
        explicit?.let { resolve(packagePath,it.getAttribute("href"))?.let { path -> bytes(path,MAX_IMAGE) } }?.let { return it }
        // A cover may be the first spine page rather than an OPF-designated cover image.
        val firstId=opf.elements("itemref").firstOrNull()?.getAttribute("idref")
        val first=items.firstOrNull { it.getAttribute("id")==firstId }
        val page=first?.let { resolve(packagePath,it.getAttribute("href")) }
        if(first?.getAttribute("media-type")?.startsWith("image/")==true) return page?.let { bytes(it,MAX_IMAGE) }
        page?.let { path ->
            val content=runCatching { xml(path) }.getOrNull()
            val href=content?.elements("img")?.firstOrNull()?.getAttribute("src")
                ?: content?.elements("image")?.firstOrNull()?.let { it.getAttributeNS("http://www.w3.org/1999/xlink","href").ifEmpty { it.getAttribute("href") } }
            href?.let { resolve(path,it) }?.let { bytes(it,MAX_IMAGE) }?.let { return it }
        }
        items.firstOrNull { it.getAttribute("media-type").startsWith("image/") }?.let { item -> resolve(packagePath,item.getAttribute("href"))?.let { bytes(it,MAX_IMAGE) } }
    }
}
