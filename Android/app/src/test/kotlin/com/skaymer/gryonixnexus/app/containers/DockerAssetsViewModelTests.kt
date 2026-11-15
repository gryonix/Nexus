package com.skaymer.gryonixnexus.app.containers

import com.skaymer.gryonixnexus.agentcontrol.DockerAssetException
import com.skaymer.gryonixnexus.agentcontrol.DockerAssetManaging
import com.skaymer.gryonixnexus.agentcontrol.DockerImageSummary
import com.skaymer.gryonixnexus.agentcontrol.DockerPruneSummary
import com.skaymer.gryonixnexus.agentcontrol.DockerVolumeSummary
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class DockerAssetsViewModelTests {
    private val server = Deployment(
        id = "S-1", name = "middle", topology = Topology.SINGLE_HOST, domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"), services = emptySet(),
    )

    private class Engine(var refuse: Boolean = false) : DockerAssetManaging {
        var imageList = mutableListOf(DockerImageSummary("old:1", "old:1", 50, 0, ""))
        val volumeList = listOf(
            DockerVolumeSummary("keep", 9, 0, isManaged = true),
            DockerVolumeSummary("free", 5, 0, isManaged = false),
        )

        override suspend fun images() = imageList.toList()
        override suspend fun volumes() = volumeList

        override suspend fun removeImage(reference: String) {
            if (refuse) throw DockerAssetException("a container still uses this image")
            imageList.removeAll { it.reference == reference }
        }

        override suspend fun removeVolume(name: String) = Unit

        override suspend fun pruneUnused(images: Boolean, volumes: Boolean): DockerPruneSummary {
            imageList.clear()
            return DockerPruneSummary(1, 1, 55, emptyList())
        }
    }

    @Test
    fun `only unused unmanaged volumes can be removed`() {
        val engine = Engine()
        assertEquals(listOf("free"), engine.volumeList.filter { it.isRemovable }.map { it.name })
    }

    @Test
    fun `removing an image reloads the list`() = runTest(StandardTestDispatcher()) {
        val engine = Engine()
        val model = DockerAssetsViewModel(this, { engine })
        model.load(server)
        runCurrent()
        assertTrue(model.state.value.hasUnused)
        assertEquals(55, model.state.value.reclaimableBytes)
        model.removeImage(server, model.state.value.images.single())
        runCurrent()
        assertTrue(model.state.value.images.isEmpty())
        assertNull(model.state.value.errorMessage)
    }

    @Test
    fun `a refusal is shown and the list is kept`() = runTest(StandardTestDispatcher()) {
        val engine = Engine(refuse = true)
        val model = DockerAssetsViewModel(this, { engine })
        model.load(server)
        runCurrent()
        model.removeImage(server, model.state.value.images.single())
        runCurrent()
        assertEquals("a container still uses this image", model.state.value.errorMessage)
        assertEquals(1, model.state.value.images.size)
    }

    @Test
    fun `prune reports what was freed`() = runTest(StandardTestDispatcher()) {
        val engine = Engine()
        val model = DockerAssetsViewModel(this, { engine })
        model.load(server)
        runCurrent()
        model.pruneUnused(server)
        runCurrent()
        assertNotNull(model.state.value.lastPrune)
        assertFalse(model.state.value.images.isNotEmpty())
    }
}
