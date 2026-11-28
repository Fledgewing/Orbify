// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion.server.bookorbit

import net.fledgewing.orbitcompanion.*
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.io.ByteArrayOutputStream
import java.nio.file.Files
import java.util.concurrent.Executors
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LocalBookCoversTest {
    private fun zip(file: File, entries: Map<String,ByteArray>) = ZipOutputStream(file.outputStream()).use { zip ->
        entries.forEach { (name,bytes) -> zip.putNextEntry(ZipEntry(name));zip.write(bytes);zip.closeEntry() }
    }
    private fun image(color: Int): ByteArray {
        val bitmap=Bitmap.createBitmap(800,1200,Bitmap.Config.ARGB_8888).apply { eraseColor(color) }
        return try { ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) }.toByteArray() } finally { bitmap.recycle() }
    }
    private fun epub(file: File, declaration: String, extra: String="") {
        zip(file,mapOf(
            "META-INF/container.xml" to "<container><rootfiles><rootfile full-path='OPS/book.opf'/></rootfiles></container>".toByteArray(),
            "OPS/book.opf" to "<package><metadata>$extra</metadata><manifest><item id='decoy' href='images/decoy.png' media-type='image/png'/><item id='art' href='images/jacket.png' media-type='image/png' $declaration/></manifest></package>".toByteArray(),
            "OPS/images/jacket.png" to image(Color.RED),"OPS/images/decoy.png" to image(Color.BLUE)))
    }
    @Test fun epub2And3CoversAreCachedAtAllSizesAndInvalidateWithTheFile() {
        val root=Files.createTempDirectory("embedded-covers").toFile()
        val worker=Executors.newSingleThreadExecutor()
        try {
            val cache=LocalBookCovers(File(root,"cache"))
            for(declaration in listOf("properties='cover-image'","")) {
                val book=File(root,"fixture.epub")
                epub(book,declaration,if(declaration.isEmpty()) "<meta name='cover' content='art'/>" else "")
                assertArrayEquals(image(Color.RED),cache.embedded(book))
                val first=worker.submit<File?> { cache.cover(book) }.get()!!
                assertTrue(first.isFile)
                for(size in LocalBookCovers.sizes) {
                    val cover=worker.submit<File?> { cache.cover(book,size=size) }.get()!!
                    val bitmap=BitmapFactory.decodeFile(cover.path)
                    assertEquals(size.first,bitmap.width);assertEquals(size.second,bitmap.height);bitmap.recycle()
                }
                val stamp=first.lastModified()
                assertEquals(first,worker.submit<File?> { cache.cover(book) }.get())
                assertEquals(stamp,first.lastModified())
                book.setLastModified(book.lastModified()+10000)
                val changed=worker.submit<File?> { cache.cover(book) }.get()!!
                assertNotEquals(first,changed);assertFalse(first.exists())
            }
        } finally { worker.shutdownNow();root.deleteRecursively() }
    }
    @Test fun cbzUsesFirstPageAndEpubUsesFirstSpineImageWithoutACoverDeclaration() {
        val root=Files.createTempDirectory("first-page").toFile()
        try {
            val cache=LocalBookCovers(File(root,"cache"))
            val cbz=File(root,"fixture.cbz")
            val first=image(Color.RED)
            zip(cbz,linkedMapOf("10.png" to image(Color.BLUE),"2.png" to first))
            assertArrayEquals(first,cache.embedded(cbz))
            val epub=File(root,"fixture.epub")
            zip(epub,mapOf("META-INF/container.xml" to "<container><rootfile full-path='book.opf'/></container>".toByteArray(),
                "book.opf" to "<package><manifest><item id='p' href='page.xhtml'/></manifest><spine><itemref idref='p'/></spine></package>".toByteArray(),
                "page.xhtml" to "<html><img src='2.png'/></html>".toByteArray(),"2.png" to first))
            assertArrayEquals(first,cache.embedded(epub))
            zip(epub,mapOf("META-INF/container.xml" to "<!DOCTYPE x [<!ENTITY e SYSTEM 'file:///private/secret'>]><container>&e;</container>".toByteArray()))
            assertTrue(runCatching { cache.embedded(epub) }.isFailure)
        } finally { root.deleteRecursively() }
    }
    @Test fun pdfFirstPageAndSidecarChangeAreWorkerOnly() {
        val root=Files.createTempDirectory("pdf-cover").toFile()
        val worker=Executors.newSingleThreadExecutor()
        try {
            val book=File(root,"fixture.pdf")
            val objects=listOf("<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 450] /Contents 4 0 R /Resources << >> >>",
                "<< /Length 26 >>\nstream\n0 0 1 rg 0 0 300 450 re f\nendstream")
            val pdf=StringBuilder("%PDF-1.4\n")
            val offsets=objects.mapIndexed { i,obj -> pdf.length.also { pdf.append("${i+1} 0 obj\n$obj\nendobj\n") } }
            val xref=pdf.length
            pdf.append("xref\n0 5\n0000000000 65535 f \n")
            offsets.forEach { pdf.append("%010d 00000 n \n".format(it)) }
            pdf.append("trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n")
            book.writeText(pdf.toString())
            // Robolectric has no PdfRenderer shadow. Exercise PDF dispatch/cache here;
            // the emulator gallery checks Android's real first-page renderer.
            var renders=0
            val cache=LocalBookCovers(File(root,"cache"),firstPdfPage={ file ->
                assertEquals(book,file);renders++
                Bitmap.createBitmap(600,900,Bitmap.Config.ARGB_8888).apply { eraseColor(Color.BLUE) }
            })
            assertNull(cache.cover(book))
            assertNotNull(worker.submit<File?> { cache.cover(book) }.get());assertEquals(1,renders)
            // A native sidecar takes priority, and invalidates independently of the PDF.
            val sidecar=File(root,"cover.png").apply { writeBytes(image(Color.RED)) }
            val first=worker.submit<File?> { cache.cover(book,sidecar) }.get()!!
            sidecar.writeBytes(image(Color.BLUE));sidecar.setLastModified(sidecar.lastModified()+10000)
            assertNotEquals(first,worker.submit<File?> { cache.cover(book,sidecar) }.get())
            assertNull(worker.submit<File?> { LocalBookCovers(File(root,"broken-cache")).cover(File(root,"broken.pdf").apply { writeText("broken") }) }.get())
        } finally { worker.shutdownNow();root.deleteRecursively() }
    }
}
