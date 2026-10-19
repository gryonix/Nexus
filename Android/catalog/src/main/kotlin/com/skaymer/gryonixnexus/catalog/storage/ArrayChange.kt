package com.skaymer.gryonixnexus.catalog.storage

/** One change to a running array */
data class ArrayChange(
    val action: Action,
    val array: StorageArray,
    /** The member taken out or replaced */
    val member: String? = null,
    /** New disks, erased and put in */
    val disks: List<ServerDisk> = emptyList(),
    /** The level after a level change */
    val level: RaidPlan.Level? = null,
) {
    enum class Action(val raw: String) {
        ADD_SPARE("add-spare"), GROW("grow"), REPLACE("replace"), DETACH("detach"),
        REMOVE("remove"), CHANGE_LEVEL("change-level"), CHECK("check"), DELETE("delete");

        /** Disks it takes from the free ones */
        fun newDisks(array: StorageArray): Int = when (this) {
            ADD_SPARE, REPLACE -> 1
            GROW -> if (array.kind == StorageArray.Kind.ZFS && array.raidLevel == RaidPlan.Level.RAID10) 2 else 1
            CHANGE_LEVEL -> if (array.kind == StorageArray.Kind.MD) 1 else 0
            DETACH, REMOVE, CHECK, DELETE -> 0
        }

        /** Whether the user picks a member to act on */
        val takesMember: Boolean get() = this == REPLACE || this == DETACH || this == REMOVE

        companion object {
            fun of(raw: String): Action? = entries.firstOrNull { it.raw == raw }
        }
    }

    val isReady: Boolean
        get() = (!action.takesMember || member in array.members) &&
            disks.size == action.newDisks(array) &&
            (action != Action.CHANGE_LEVEL || level in levels(array))

    companion object {
        const val DONE_MARKER = "GRYONIXNEXUS_ARRAY_CHANGE_DONE"

        /** Arrays whose disks this app changes */
        fun manages(array: StorageArray): Boolean =
            array.kind in setOf(StorageArray.Kind.MD, StorageArray.Kind.ZFS, StorageArray.Kind.BTRFS) &&
                !array.isForeignSystemPool && array.state != StorageArray.State.Stopped &&
                array.state != StorageArray.State.Unknown &&
                (array.kind != StorageArray.Kind.BTRFS || array.mountpoint != null)

        /** What can be done to the array right now */
        fun actions(array: StorageArray, hardware: ServerHardware): List<Action> {
            if (!manages(array)) return emptyList()
            val free = RaidPlan.candidates(hardware).size
            val healthy = array.state == StorageArray.State.Clean
            return Action.entries.filter { action ->
                free >= action.newDisks(array) && when (action) {
                    Action.CHECK -> healthy
                    Action.DELETE -> !array.isCacheMirror
                    else -> healthy && ArrayRules.allows(action, array)
                }
            }
        }

        /** Levels a level change may go to */
        fun levels(array: StorageArray): List<RaidPlan.Level> = ArrayRules.levelTargets(array)
    }
}

/** The level in RAID terms, whatever tool built it */
val StorageArray.raidLevel: RaidPlan.Level?
    get() = when {
        kind == StorageArray.Kind.ZFS -> when (level) {
            "stripe" -> RaidPlan.Level.RAID0
            "mirror" -> if (groups > 1) RaidPlan.Level.RAID10 else RaidPlan.Level.RAID1
            "raidz1" -> RaidPlan.Level.RAID5
            "raidz2" -> RaidPlan.Level.RAID6
            else -> null
        }
        level.startsWith("raid") -> level.removePrefix("raid").toIntOrNull()?.let(RaidPlan.Level::of)
        else -> null
    }

/** Which change each kind and level of array allows */
internal object ArrayRules {
    private val REDUNDANT = setOf(RaidPlan.Level.RAID1, RaidPlan.Level.RAID5, RaidPlan.Level.RAID6, RaidPlan.Level.RAID10)

    fun allows(action: ArrayChange.Action, array: StorageArray): Boolean {
        val level = array.raidLevel
        val count = array.members.size
        return when (array.kind to action) {
            StorageArray.Kind.MD to ArrayChange.Action.ADD_SPARE,
            StorageArray.Kind.MD to ArrayChange.Action.REPLACE -> level != null && level != RaidPlan.Level.RAID0
            StorageArray.Kind.MD to ArrayChange.Action.GROW ->
                level in setOf(RaidPlan.Level.RAID1, RaidPlan.Level.RAID5, RaidPlan.Level.RAID6)
            StorageArray.Kind.MD to ArrayChange.Action.DETACH -> level in REDUNDANT
            StorageArray.Kind.MD to ArrayChange.Action.REMOVE -> mdShrinks(array)
            StorageArray.Kind.ZFS to ArrayChange.Action.ADD_SPARE -> level != null && level != RaidPlan.Level.RAID0
            StorageArray.Kind.ZFS to ArrayChange.Action.GROW -> level != null
            StorageArray.Kind.ZFS to ArrayChange.Action.REPLACE -> true
            StorageArray.Kind.ZFS to ArrayChange.Action.DETACH -> level in REDUNDANT
            StorageArray.Kind.ZFS to ArrayChange.Action.REMOVE ->
                (level == RaidPlan.Level.RAID1 || level == RaidPlan.Level.RAID0) && count >= 2
            StorageArray.Kind.BTRFS to ArrayChange.Action.GROW,
            StorageArray.Kind.BTRFS to ArrayChange.Action.REPLACE -> true
            StorageArray.Kind.BTRFS to ArrayChange.Action.REMOVE -> count - 1 >= (level?.minimumDisks ?: 1)
            else -> action == ArrayChange.Action.CHANGE_LEVEL && levelTargets(array).isNotEmpty()
        }
    }

    /** Whether md can drop a member at this level */
    private fun mdShrinks(array: StorageArray): Boolean {
        val count = array.members.size
        return when (array.raidLevel) {
            RaidPlan.Level.RAID1 -> count >= 2
            RaidPlan.Level.RAID5 -> count >= 4 && array.filesystem == "ext4"
            RaidPlan.Level.RAID6 -> count >= 5 && array.filesystem == "ext4"
            else -> false
        }
    }

    fun levelTargets(array: StorageArray): List<RaidPlan.Level> = when {
        array.kind == StorageArray.Kind.MD && array.raidLevel == RaidPlan.Level.RAID1 ->
            if (array.members.size == 2) listOf(RaidPlan.Level.RAID5) else emptyList()
        array.kind == StorageArray.Kind.MD && array.raidLevel == RaidPlan.Level.RAID5 -> listOf(RaidPlan.Level.RAID6)
        array.kind == StorageArray.Kind.BTRFS -> RaidPlan.levels(StorageArray.Kind.BTRFS)
            .filter { it != array.raidLevel && array.members.size >= it.minimumDisks }
        else -> emptyList()
    }
}
