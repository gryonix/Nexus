package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import org.junit.jupiter.api.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TerminalAccessoryKeysTests {
    @Test
    fun catalogIdsAreUniqueAndDefaultsResolve() {
        val ids = AccessoryCatalog.all.map { it.id }
        assertEquals(ids.size, ids.toSet().size)
        assertEquals(AccessoryLayout.DEFAULT_IDS.size, AccessoryLayout().keys.size)
    }

    @Test
    fun functionKeySequences() {
        assertContentEquals("\u001BOP".toByteArray(), (AccessoryCatalog.key("f1")!!.action as AccessoryKey.Action.Bytes).bytes)
        assertContentEquals("\u001B[15~".toByteArray(), (AccessoryCatalog.key("f5")!!.action as AccessoryKey.Action.Bytes).bytes)
        assertContentEquals(byteArrayOf(3), (AccessoryCatalog.key("ctrl-C")!!.action as AccessoryKey.Action.Bytes).bytes)
    }

    @Test
    fun addRemoveMoveReset() {
        var layout = AccessoryLayout(listOf("esc", "tab")).adding("f1").adding("f1").adding("nonsense")
        assertEquals(listOf("esc", "tab", "f1"), layout.ids)
        layout = layout.moving(2, 0)
        assertEquals(listOf("f1", "esc", "tab"), layout.ids)
        layout = layout.removing(1)
        assertEquals(listOf("f1", "tab"), layout.ids)
        assertEquals(AccessoryLayout.DEFAULT_IDS, layout.reset().ids)
    }

    @Test
    fun storeRoundTrip() {
        val store = AccessoryLayoutStore(InMemorySettingsStore())
        assertEquals(AccessoryLayout(), store.load())
        val layout = AccessoryLayout(listOf("tab", "sym-|"))
        store.save(layout)
        assertEquals(layout, store.load())
        assertTrue(store.load().keys.size == 2)
    }
}
