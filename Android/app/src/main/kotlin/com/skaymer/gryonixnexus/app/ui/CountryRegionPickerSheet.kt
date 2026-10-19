package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.RowLabel

private const val MAP_SCROLLS_KEY = "countryPicker.mapScrolls"

@Composable
fun CountryRegionPickerSheet(
    codes: List<String>,
    onCodesChange: (List<String>) -> Unit,
    store: SettingsStore,
    onClose: () -> Unit,
) {
    val selected = remember(codes) { codes.toSet() }
    var mapScrolls by remember { mutableStateOf(store.boolean(MAP_SCROLLS_KEY) ?: false) }
    var fullScreenMap by remember { mutableStateOf(false) }
    val toggle: (String) -> Unit = { code ->
        val next = codes.toMutableSet()
        if (!next.remove(code)) next.add(code)
        onCodesChange(next.sorted())
    }

    IOSSheet(
        title = stringResource(R.string.security_auto_countries),
        onClose = onClose,
        closeLabel = stringResource(R.string.group_done),
        scrollable = false,
        trailing = {
            MapMenu(mapScrolls) {
                mapScrolls = it
                store.setBoolean(MAP_SCROLLS_KEY, it)
            }
        },
    ) {
        if (!mapScrolls) MapCard(selected, toggle) { fullScreenMap = true }
        Column(
            Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(Metrics.sectionGap),
        ) {
            if (mapScrolls) MapCard(selected, toggle) { fullScreenMap = true }
            ContinentsSection(codes, selected, onCodesChange)
            RegionsSection(codes, selected, onCodesChange)
            CountriesSection(selected, toggle)
        }
    }
    if (fullScreenMap) FullScreenMap(selected, toggle) { fullScreenMap = false }
}

@Composable
private fun MapCard(selected: Set<String>, onToggle: (String) -> Unit, onExpand: () -> Unit) {
    WorldMapCanvas(
        selected = selected,
        description = stringResource(R.string.world_map_selected, selected.size),
        onToggle = onToggle,
        modifier = Modifier
            .padding(horizontal = Metrics.listInset)
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(Gryonix.colors.cardBackground)
            .padding(10.dp),
        onExpand = onExpand,
    )
}

@Composable
private fun FullScreenMap(selected: Set<String>, onToggle: (String) -> Unit, onClose: () -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        IOSSheet(
            title = stringResource(R.string.security_auto_countries),
            onClose = onClose,
            closeLabel = stringResource(R.string.group_done),
            scrollable = false,
        ) {
            WorldMapCanvas(
                selected = selected,
                description = stringResource(R.string.world_map_selected, selected.size),
                onToggle = onToggle,
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = Metrics.listInset)
                    .fillMaxWidth(),
                fillsSpace = true,
            )
        }
    }
}

@Composable
private fun MapMenu(mapScrolls: Boolean, onChange: (Boolean) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }) {
            Icon(Icons.Filled.MoreHoriz, contentDescription = stringResource(R.string.more),
                tint = Gryonix.colors.accent)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.map_scrolls_with_list)) },
                leadingIcon = { Icon(Icons.Filled.Map, contentDescription = null) },
                trailingIcon = { if (mapScrolls) Icon(Icons.Filled.Check, contentDescription = null) },
                onClick = { open = false; onChange(!mapScrolls) },
            )
        }
    }
}

@Composable
private fun ContinentsSection(
    codes: List<String>,
    selected: Set<String>,
    onCodesChange: (List<String>) -> Unit,
) {
    GroupedSection(
        header = stringResource(R.string.security_continents),
        note = stringResource(R.string.security_continents_note),
    ) {
        val continents = Continent.entries
        continents.forEachIndexed { index, continent ->
            GroupMembersRow(
                title = stringResource(continent.titleRes),
                members = remember(continent) { CountryCatalog.codesIn(continent) },
                codes = codes,
                selected = selected,
                showDivider = index != continents.lastIndex,
                onCodesChange = onCodesChange,
            )
        }
    }
}

@Composable
private fun RegionsSection(
    codes: List<String>,
    selected: Set<String>,
    onCodesChange: (List<String>) -> Unit,
) {
    GroupedSection(
        header = stringResource(R.string.security_auto_regions),
        note = stringResource(R.string.security_auto_regions_note),
    ) {
        val regions = CountryRegion.entries
        regions.forEachIndexed { index, region ->
            GroupMembersRow(
                title = stringResource(region.titleRes),
                members = remember(region) { CountryCatalog.codesIn(region) },
                codes = codes,
                selected = selected,
                showDivider = index != regions.lastIndex,
                onCodesChange = onCodesChange,
            )
        }
    }
}

@Composable
private fun GroupMembersRow(
    title: String,
    members: List<String>,
    codes: List<String>,
    selected: Set<String>,
    showDivider: Boolean,
    onCodesChange: (List<String>) -> Unit,
) {
    val selectedCount = remember(selected, members) { members.count(selected::contains) }
    RegionRow(
        title = title,
        selectedCount = selectedCount,
        total = members.size,
        showDivider = showDivider,
        onClick = {
            val next = codes.toMutableSet()
            if (selectedCount == members.size) members.forEach(next::remove) else members.forEach(next::add)
            onCodesChange(next.sorted())
        },
    )
}

@Composable
private fun CountriesSection(selected: Set<String>, onToggle: (String) -> Unit) {
    var search by remember { mutableStateOf("") }
    GroupedSection(
        header = stringResource(R.string.security_auto_countries),
        note = stringResource(R.string.security_auto_countries_note),
    ) {
        FieldRow(
            label = stringResource(R.string.security_auto_search),
            value = search,
            onValueChange = { search = it },
            placeholder = stringResource(R.string.security_auto_search),
        )
        val filtered = remember(search) {
            val query = search.trim()
            CountryCatalog.allCodes
                .map { it to CountryCatalog.name(it) }
                .sortedBy { it.second }
                .filter { (code, name) ->
                    query.isEmpty() || name.contains(query, ignoreCase = true) ||
                        code.contains(query, ignoreCase = true)
                }
        }
        filtered.forEachIndexed { index, (code, name) ->
            CheckRow(
                title = listOf(CountryCatalog.flag(code), name).filter(String::isNotEmpty).joinToString(" "),
                checked = selected.contains(code),
                showDivider = index != filtered.lastIndex,
                onClick = { onToggle(code) },
            )
        }
        if (filtered.isEmpty()) {
            GroupedRow(showDivider = false) {
                RowLabel(stringResource(R.string.security_auto_no_country_match))
            }
        }
    }
}

@Composable
private fun RegionRow(
    title: String,
    selectedCount: Int,
    total: Int,
    showDivider: Boolean,
    onClick: () -> Unit,
) {
    val colors = Gryonix.colors
    GroupedRow(
        onClick = onClick,
        showDivider = showDivider,
        trailing = {
            Text(
                "$selectedCount/$total",
                style = MaterialTheme.typography.bodySmall,
                color = colors.secondaryLabel,
                modifier = Modifier.padding(end = 8.dp),
            )
            when {
                selectedCount == total -> Icon(
                    Icons.Filled.CheckCircle,
                    contentDescription = null,
                    tint = colors.accent,
                    modifier = Modifier.size(20.dp),
                )
                selectedCount > 0 -> Icon(
                    Icons.Filled.RemoveCircle,
                    contentDescription = null,
                    tint = colors.secondaryLabel,
                    modifier = Modifier.size(20.dp),
                )
                else -> Icon(
                    Icons.Filled.RadioButtonUnchecked,
                    contentDescription = null,
                    tint = colors.tertiaryLabel,
                    modifier = Modifier.size(20.dp),
                )
            }
        },
    ) {
        RowLabel(title)
    }
}
