package com.skaymer.gryonixnexus.app.ui

import kotlin.math.min

data class MapViewport(
    val contentWidth: Float,
    val contentHeight: Float,
    /** 1 fits the whole map into the view */
    val scale: Float = 1f,
    val originX: Float = 0f,
    val originY: Float = 0f,
) {
    val isZoomedIn: Boolean get() = scale > 1.0001f

    /** View pixels per map unit */
    fun pointsPerUnit(viewWidth: Float, viewHeight: Float): Float {
        if (contentWidth <= 0f || contentHeight <= 0f || viewWidth <= 0f || viewHeight <= 0f) return 0f
        return min(viewWidth / contentWidth, viewHeight / contentHeight) * scale
    }

    fun visibleWidth(viewWidth: Float, viewHeight: Float): Float {
        val perUnit = pointsPerUnit(viewWidth, viewHeight)
        return if (perUnit <= 0f) contentWidth else viewWidth / perUnit
    }

    fun visibleHeight(viewWidth: Float, viewHeight: Float): Float {
        val perUnit = pointsPerUnit(viewWidth, viewHeight)
        return if (perUnit <= 0f) contentHeight else viewHeight / perUnit
    }

    /** Inside the map, or centred when the map is smaller */
    fun visibleX(viewWidth: Float, viewHeight: Float): Float =
        clamped(originX, visibleWidth(viewWidth, viewHeight), contentWidth)

    fun visibleY(viewWidth: Float, viewHeight: Float): Float =
        clamped(originY, visibleHeight(viewWidth, viewHeight), contentHeight)

    fun reset(viewWidth: Float, viewHeight: Float): MapViewport =
        copy(scale = 1f, originX = 0f, originY = 0f).settled(viewWidth, viewHeight)

    /** Keeps the map point under the fingers where it is */
    fun zoom(factor: Float, anchorX: Float, anchorY: Float, viewWidth: Float, viewHeight: Float):
        MapViewport {
        val beforeX = mapX(anchorX, viewWidth, viewHeight)
        val beforeY = mapY(anchorY, viewWidth, viewHeight)
        val zoomed = copy(scale = (scale * factor).coerceIn(1f, MAX_SCALE))
        return zoomed.copy(
            originX = zoomed.originX + beforeX - zoomed.mapX(anchorX, viewWidth, viewHeight),
            originY = zoomed.originY + beforeY - zoomed.mapY(anchorY, viewWidth, viewHeight),
        ).settled(viewWidth, viewHeight)
    }

    /** Moves the map with the finger */
    fun pan(dx: Float, dy: Float, viewWidth: Float, viewHeight: Float): MapViewport {
        val perUnit = pointsPerUnit(viewWidth, viewHeight)
        if (perUnit <= 0f) return this
        return copy(originX = originX - dx / perUnit, originY = originY - dy / perUnit)
            .settled(viewWidth, viewHeight)
    }

    fun mapX(viewX: Float, viewWidth: Float, viewHeight: Float): Float {
        val perUnit = pointsPerUnit(viewWidth, viewHeight)
        return if (perUnit <= 0f) originX else visibleX(viewWidth, viewHeight) + viewX / perUnit
    }

    fun mapY(viewY: Float, viewWidth: Float, viewHeight: Float): Float {
        val perUnit = pointsPerUnit(viewWidth, viewHeight)
        return if (perUnit <= 0f) originY else visibleY(viewWidth, viewHeight) + viewY / perUnit
    }

    private fun settled(viewWidth: Float, viewHeight: Float): MapViewport =
        copy(originX = visibleX(viewWidth, viewHeight), originY = visibleY(viewWidth, viewHeight))

    private fun clamped(value: Float, visible: Float, content: Float): Float {
        val slack = content - visible
        return if (slack <= 0f) slack / 2f else value.coerceIn(0f, slack)
    }

    companion object {
        const val MAX_SCALE = 12f
    }
}
