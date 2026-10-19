package com.skaymer.gryonixnexus.app.servers

object MetricBlock {
    /** The wide card */
    const val WIDE = 93f

    /** The half-width card, whose rows are a type size smaller */
    const val COMPACT = 75f

    /** The least air between two rows */
    const val WIDE_GAP = 4f
    const val COMPACT_GAP = 3f

    const val TRAFFIC_GAP = 6f

    /** Between the network line and the disk line */
    const val TRAFFIC_LINE_GAP = 2f

    const val LABEL_HEIGHT = 17f

    const val STACKED_LABEL_WIDTH = 44f
    const val STACKED_LABEL_GAP = 6f

    /** Air between neighbouring rings, side by side and stacked */
    const val RING_GUTTER = 12f
    const val STACKED_RING_GUTTER = 6f

    const val RING_FLOOR = 28f

    fun height(compact: Boolean): Float = if (compact) COMPACT else WIDE

    fun gap(compact: Boolean): Float = if (compact) COMPACT_GAP else WIDE_GAP
}

/** How big a ring is drawn in that block */
object RingLayout {
    fun diameter(
        width: Float,
        height: Float,
        count: Int,
        gutter: Float = MetricBlock.RING_GUTTER,
        labelHeight: Float = MetricBlock.LABEL_HEIGHT,
        floor: Float = MetricBlock.RING_FLOOR,
        outerAir: Boolean = false,
    ): Float {
        val rings = maxOf(count, 1)
        val gutters = if (outerAir) maxOf(count, 1) else maxOf(count - 1, 0)
        val byWidth = (width - gutter * gutters) / rings
        return maxOf(floor, minOf(byWidth, height - labelHeight))
    }

    /** The diameter three rings get standing one UNDER another */
    fun stackedDiameter(
        width: Float,
        height: Float,
        count: Int,
        gutter: Float = MetricBlock.STACKED_RING_GUTTER,
        labelWidth: Float = MetricBlock.STACKED_LABEL_WIDTH,
        floor: Float = MetricBlock.RING_FLOOR,
    ): Float {
        val rings = maxOf(count, 1)
        val byHeight = (height - gutter * maxOf(count - 1, 0)) / rings
        val byWidth = width - labelWidth - MetricBlock.STACKED_LABEL_GAP
        return maxOf(floor, minOf(byWidth, byHeight))
    }

    fun stacks(width: Float, height: Float, count: Int): Boolean =
        stackedDiameter(width, height, count) > diameter(width, height, count)
}
