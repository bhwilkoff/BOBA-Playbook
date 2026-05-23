package com.bobaplaybook.app.feature.scan

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure-JVM tests for the session queue. The store has no Android
 * dependencies — just `kotlinx.coroutines.flow.StateFlow` — so it tests
 * cleanly without Robolectric.
 *
 * Critical assertion: iOS-parity de-dupe (ScanStore.addToQueue line ~138).
 * Scanning the same card twice does NOT create two rows; it bumps the
 * existing row's quantity. Whatnot box-break workflow: 3 copies of
 * Maverick → queue shows one "Maverick ×3" row, not three "Maverick" rows.
 */
class ScanQueueStoreTest {

    @Test
    fun `first append creates a single-quantity entry`() {
        val store = ScanQueueStore()
        store.append("1-Maverick--")
        val entries = store.entries.value
        assertEquals(1, entries.size)
        assertEquals(1, entries[0].quantity)
        assertEquals("1-Maverick--", entries[0].bobaId)
    }

    @Test
    fun `second append of same bobaId bumps quantity instead of duplicating`() {
        val store = ScanQueueStore()
        store.append("1-Maverick--")
        store.append("1-Maverick--")
        store.append("1-Maverick--")
        val entries = store.entries.value
        assertEquals("Should collapse 3 dupes to 1 row", 1, entries.size)
        assertEquals("Quantity should reflect 3 scans", 3, entries[0].quantity)
    }

    @Test
    fun `different bobaIds remain distinct rows`() {
        val store = ScanQueueStore()
        store.append("1-Maverick--")
        store.append("20-Tigre--")
        store.append("BHBF-37-JacHammer--")
        val entries = store.entries.value
        assertEquals(3, entries.size)
        // Most-recent first — Tigre and JacHammer push onto the head.
        assertEquals("BHBF-37-JacHammer--", entries[0].bobaId)
        assertEquals("20-Tigre--", entries[1].bobaId)
        assertEquals("1-Maverick--", entries[2].bobaId)
    }

    @Test
    fun `quantity clamps at 99`() {
        val store = ScanQueueStore()
        repeat(150) { store.append("1-Maverick--") }
        val entry = store.entries.value.single()
        assertEquals(99, entry.quantity)
    }

    @Test
    fun `setQuantity overrides the row's count`() {
        val store = ScanQueueStore()
        store.append("1-Maverick--")
        store.setQuantity("1-Maverick--", 7)
        assertEquals(7, store.entries.value.single().quantity)
    }

    @Test
    fun `setQuantity clamps to 1-99`() {
        val store = ScanQueueStore()
        store.append("1-Maverick--")
        store.setQuantity("1-Maverick--", -5)
        assertEquals("Should clamp to 1", 1, store.entries.value.single().quantity)
        store.setQuantity("1-Maverick--", 250)
        assertEquals("Should clamp to 99", 99, store.entries.value.single().quantity)
    }

    @Test
    fun `remove drops the entry entirely`() {
        val store = ScanQueueStore()
        store.append("1-Maverick--")
        store.append("20-Tigre--")
        store.remove("1-Maverick--")
        val entries = store.entries.value
        assertEquals(1, entries.size)
        assertEquals("20-Tigre--", entries[0].bobaId)
    }

    @Test
    fun `clear empties the queue`() {
        val store = ScanQueueStore()
        repeat(3) { store.append("card-$it") }
        store.clear()
        assertTrue(store.entries.value.isEmpty())
    }

    @Test
    fun `blank bobaId is ignored`() {
        val store = ScanQueueStore()
        store.append("")
        store.append("   ")
        assertTrue("Blank/whitespace bobaIds should not enter the queue",
            store.entries.value.isEmpty())
    }

    @Test
    fun `cap at 25 entries — oldest distinct cards drop`() {
        val store = ScanQueueStore()
        repeat(30) { store.append("card-$it") }
        val entries = store.entries.value
        assertEquals(25, entries.size)
        // Most recent at the head; oldest 5 distinct cards dropped.
        assertEquals("card-29", entries[0].bobaId)
    }
}
