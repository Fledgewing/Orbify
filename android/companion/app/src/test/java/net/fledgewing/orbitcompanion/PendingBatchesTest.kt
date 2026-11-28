// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

import java.util.concurrent.Executor
import java.util.concurrent.RejectedExecutionException
import org.junit.Assert.*
import org.junit.Test

class PendingBatchesTest {
    @Test fun repeatedPaintsShareOneQueuedAndRunningPublication() {
        val pending=PendingBatches();val queue=mutableListOf<Runnable>();val executor=Executor { queue+=it }
        var calls=0
        assertTrue(pending.submit("same",executor) {
            calls++
            assertFalse(pending.submit("same",executor) { error("duplicate running publication") })
        })
        repeat(100) { assertFalse(pending.submit("same",executor) { error("duplicate queued publication") }) }
        assertEquals(1,queue.size);queue.removeAt(0).run();assertEquals(1,calls)
        assertTrue(pending.submit("same",executor) { calls++ });queue.removeAt(0).run();assertEquals(2,calls)
    }
    @Test fun differentVisibleRequestsAreNeverDropped() {
        val pending=PendingBatches();val queue=mutableListOf<Runnable>();val executor=Executor { queue+=it }
        val published=mutableListOf<String>()
        for(key in listOf("home","library","settings")) assertTrue(pending.submit(key,executor) { published+=key })
        queue.forEach { it.run() };assertEquals(listOf("home","library","settings"),published)
    }
    @Test fun aFailedPublicationCanBeRequestedAgain() {
        val pending=PendingBatches();val queue=mutableListOf<Runnable>();val executor=Executor { queue+=it }
        pending.submit("same",executor) { throw IllegalStateException("publication failed") }
        try { queue.removeAt(0).run();fail("expected the real failure") } catch(_:IllegalStateException) {}
        assertTrue(pending.submit("same",executor) {})
    }
    @Test fun executorRejectionDoesNotPinTheRequest() {
        val pending=PendingBatches()
        try { pending.submit("same",Executor { throw RejectedExecutionException() }) {};fail("expected rejection") }
        catch(_:RejectedExecutionException) {}
        assertTrue(pending.submit("same",Executor { it.run() }) {})
    }
}
