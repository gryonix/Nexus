package com.skaymer.gryonixnexus.servercontrol

data class DiskRowPlan(
    val primary: List<DiskMount>,
    val namesPrimaryByTarget: Boolean,
    /** The rows behind the "Other volumes" disclosure */
    val others: List<DiskMount>,
) {
    companion object {
        fun make(mounts: List<DiskMount>): DiskRowPlan {
            val root = mounts.firstOrNull { it.target == "/" }
                ?: return DiskRowPlan(
                    primary = mounts,
                    namesPrimaryByTarget = true,
                    others = emptyList(),
                )
            return DiskRowPlan(
                primary = listOf(root),
                namesPrimaryByTarget = false,
                others = mounts.filter { it.target != "/" },
            )
        }
    }
}
