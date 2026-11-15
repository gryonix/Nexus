package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.agentcontrol.DockerImageSummary
import com.skaymer.gryonixnexus.agentcontrol.DockerNetworkSummary
import com.skaymer.gryonixnexus.agentcontrol.DockerVolumeSummary
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.containers.DockerAssetsViewModel
import com.skaymer.gryonixnexus.app.servers.MetricsFormat
import com.skaymer.gryonixnexus.app.shell.AppModule
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.servercontrol.Deployment

enum class DockerTab { CONTAINERS, IMAGES, VOLUMES, NETWORKS, SYSTEM }

/** Containers, images and volumes of one server, one tab each */
@Composable
fun DockerTabs(deployment: Deployment, containersList: @Composable () -> Unit) {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val serverSets by app.modules.servers.collectAsState()
    val kept by app.modules.keptOnServers.collectAsState()
    var tab by remember(deployment.id) { mutableStateOf(DockerTab.CONTAINERS) }
    val advanced = setOf(DockerTab.NETWORKS, DockerTab.SYSTEM)
    val dockerAdvanced = remember(serverSets, kept) { app.modules.isOn(AppModule.DOCKER_ADVANCED, deployment.id) }
    val tabs = DockerTab.entries.filter { it !in advanced || dockerAdvanced }
    Column(Modifier.fillMaxSize()) {
        IOSSegmentedControl(
            segments = tabs,
            selected = tab,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            label = { stringResource(it.titleRes) },
            onSelect = { tab = it },
        )
        if (tab == DockerTab.CONTAINERS) {
            containersList()
        } else {
            val model = remember(deployment.id) { app.dockerAssetsViewModel() }
            DockerAssetsPage(deployment, model, tab)
        }
    }
}

private val DockerTab.titleRes: Int
    get() = when (this) {
        DockerTab.CONTAINERS -> R.string.tab_containers
        DockerTab.IMAGES -> R.string.docker_images
        DockerTab.VOLUMES -> R.string.docker_volumes
        DockerTab.NETWORKS -> R.string.docker_networks
        DockerTab.SYSTEM -> R.string.docker_system
    }

@Composable
private fun DockerAssetsPage(deployment: Deployment, model: DockerAssetsViewModel, tab: DockerTab) {
    val state by model.state.collectAsState()
    var image by remember { mutableStateOf<DockerImageSummary?>(null) }
    var volume by remember { mutableStateOf<DockerVolumeSummary?>(null) }
    var network by remember { mutableStateOf<DockerNetworkSummary?>(null) }
    var pruning by remember { mutableStateOf(false) }
    LaunchedEffect(deployment.id) { model.load(deployment) }

    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        state.errorMessage?.let { item { Note(it, isError = true) } }
        state.lastPrune?.let { item { Note(pruneText(it.imagesRemoved, it.volumesRemoved, it.reclaimedBytes)) } }
        item {
            GroupedSection {
                when (tab) {
                    DockerTab.IMAGES -> state.images.forEach { row ->
                        AssetRow(row.name, row.sizeBytes, row.isInUse, !row.isInUse, row != state.images.last()) { image = row }
                    }
                    DockerTab.VOLUMES -> state.volumes.forEach { row ->
                        AssetRow(row.name, row.sizeBytes, row.isInUse || row.isManaged, row.isRemovable,
                            row != state.volumes.last()) { volume = row }
                    }
                    DockerTab.NETWORKS -> NetworkRows(state.networks) { network = it }
                    else -> SystemRows(state.images.size, state.volumes.size, state.totalBytes, state.reclaimableBytes)
                }
            }
        }
        if (state.hasUnused && tab != DockerTab.NETWORKS) item {
            PlainButton(
                text = stringResource(R.string.docker_remove_unused),
                onClick = { pruning = true },
                modifier = Modifier.padding(horizontal = 16.dp),
                danger = true,
            )
        }
    }

    RemovalAlerts(
        deployment, model, state.reclaimableBytes,
        image, { image = it }, volume, { volume = it }, network, { network = it }, pruning, { pruning = it },
    )
}

@Composable
private fun RemovalAlerts(
    deployment: Deployment,
    model: DockerAssetsViewModel,
    reclaimableBytes: Long,
    image: DockerImageSummary?, setImage: (DockerImageSummary?) -> Unit,
    volume: DockerVolumeSummary?, setVolume: (DockerVolumeSummary?) -> Unit,
    network: DockerNetworkSummary?, setNetwork: (DockerNetworkSummary?) -> Unit,
    pruning: Boolean, setPruning: (Boolean) -> Unit,
) {
    image?.let { target ->
        ConfirmAlert(
            title = stringResource(R.string.docker_remove_image),
            message = target.name,
            confirm = stringResource(R.string.docker_remove),
            destructive = true,
            onConfirm = { setImage(null); model.removeImage(deployment, target) },
            onCancel = { setImage(null) },
        )
    }
    volume?.let { target ->
        ConfirmAlert(
            title = stringResource(R.string.docker_remove_volume),
            message = stringResource(R.string.docker_remove_volume_hint),
            confirm = stringResource(R.string.docker_remove),
            destructive = true,
            onConfirm = { setVolume(null); model.removeVolume(deployment, target) },
            onCancel = { setVolume(null) },
        )
    }
    network?.let { target ->
        ConfirmAlert(
            title = stringResource(R.string.docker_remove_network),
            message = target.name,
            confirm = stringResource(R.string.docker_remove),
            destructive = true,
            onConfirm = { setNetwork(null); model.removeNetwork(deployment, target) },
            onCancel = { setNetwork(null) },
        )
    }
    if (pruning) {
        ConfirmAlert(
            title = stringResource(R.string.docker_remove_unused_title),
            message = stringResource(R.string.docker_remove_unused_hint, MetricsFormat.bytes(reclaimableBytes)),
            confirm = stringResource(R.string.docker_remove),
            destructive = true,
            onConfirm = { setPruning(false); model.pruneUnused(deployment) },
            onCancel = { setPruning(false) },
        )
    }
}

@Composable
private fun pruneText(images: Int, volumes: Int, bytes: Long): String =
    stringResource(R.string.docker_pruned, images, volumes, MetricsFormat.bytes(bytes))

@Composable
private fun AssetRow(title: String, size: Long, inUse: Boolean, removable: Boolean, divider: Boolean, onRemove: () -> Unit) {
    val colors = Gryonix.colors
    GroupedRow(
        onLongClick = if (removable) onRemove else null,
        onClick = if (removable) onRemove else null,
        showDivider = divider,
        trailing = { Text(MetricsFormat.bytes(size), style = MaterialTheme.typography.bodySmall, color = colors.secondaryLabel) },
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = colors.label, maxLines = 1)
            Text(
                stringResource(if (inUse) R.string.docker_in_use else R.string.docker_unused),
                style = MaterialTheme.typography.bodySmall,
                color = if (inUse) colors.secondaryLabel else colors.danger,
            )
        }
    }
}

@Composable
private fun SystemRows(images: Int, volumes: Int, total: Long, reclaimable: Long) {
    val rows = listOf(
        stringResource(R.string.docker_images) to images.toString(),
        stringResource(R.string.docker_volumes) to volumes.toString(),
        stringResource(R.string.docker_disk_used) to MetricsFormat.bytes(total),
        stringResource(R.string.docker_can_free) to MetricsFormat.bytes(reclaimable),
    )
    rows.forEachIndexed { index, (label, value) ->
        GroupedRow(showDivider = index != rows.lastIndex, trailing = {
            Text(value, style = MaterialTheme.typography.bodyMedium, color = Gryonix.colors.secondaryLabel)
        }) { Text(label, style = MaterialTheme.typography.bodyLarge, color = Gryonix.colors.label) }
    }
}

@Composable
private fun Note(text: String, isError: Boolean = false) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = if (isError) Gryonix.colors.danger else Gryonix.colors.secondaryLabel,
        modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
    )
}

@Composable
private fun NetworkRows(networks: List<DockerNetworkSummary>, onRemove: (DockerNetworkSummary) -> Unit) {
    val colors = Gryonix.colors
    if (networks.isEmpty()) {
        GroupedRow(showDivider = false) {
            Text(stringResource(R.string.docker_no_networks), style = MaterialTheme.typography.bodyLarge, color = colors.secondaryLabel)
        }
    }
    networks.forEachIndexed { index, row ->
        GroupedRow(
            onClick = if (row.isRemovable) ({ onRemove(row) }) else null,
            showDivider = index != networks.lastIndex,
            trailing = {
                Text(listOf(row.driver, row.subnet).filter { it.isNotEmpty() }.joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall, color = colors.secondaryLabel)
            },
        ) {
            Column(Modifier.weight(1f)) {
                Text(row.name, style = MaterialTheme.typography.bodyLarge, color = colors.label, maxLines = 1)
                Text(networkStatus(row), style = MaterialTheme.typography.bodySmall,
                    color = if (row.isRemovable) colors.danger else colors.secondaryLabel)
            }
        }
    }
}

@Composable
private fun networkStatus(row: DockerNetworkSummary): String = when {
    row.isBuiltin -> stringResource(R.string.docker_network_builtin)
    row.isManaged -> stringResource(R.string.docker_network_managed)
    row.isInUse -> stringResource(R.string.docker_network_containers, row.containers)
    else -> stringResource(R.string.docker_unused)
}
