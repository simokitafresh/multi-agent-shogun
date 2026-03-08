package com.shogun.android.ui

import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntSize

private const val MIN_TERMINAL_SCALE = 1f
private const val MAX_TERMINAL_SCALE = 3f
private const val ABS_MIN_SCALE = 0.25f

@Stable
class TerminalZoomState(
    private val baseMinScale: Float = MIN_TERMINAL_SCALE,
    private val maxScale: Float = MAX_TERMINAL_SCALE
) {
    var scale by mutableFloatStateOf(baseMinScale)
        private set

    var offset by mutableStateOf(Offset.Zero)
        private set

    private var viewportSize by mutableStateOf(IntSize.Zero)
    private var contentWidth by mutableFloatStateOf(0f)

    val minScale: Float
        get() = if (contentWidth > 0f && viewportSize.width > 0)
            (viewportSize.width.toFloat() / contentWidth).coerceIn(ABS_MIN_SCALE, baseMinScale)
        else baseMinScale

    val isZoomed: Boolean
        get() = kotlin.math.abs(scale - 1f) > 0.01f

    val isZoomedIn: Boolean
        get() = scale > 1.01f

    /** Layout width multiplier for "desktop view" — content lays out wider when zoomed out */
    val layoutWidthMultiplier: Float
        get() = if (scale < 1f) (1f / scale) else 1f

    fun updateViewport(size: IntSize) {
        viewportSize = size
        offset = clampOffset(offset, scale)
    }

    fun updateContentWidth(width: Float) {
        if (kotlin.math.abs(contentWidth - width) > 1f) {
            contentWidth = width
        }
    }

    fun clearContentWidth() {
        contentWidth = 0f
    }

    fun onTransform(zoomChange: Float, panChange: Offset) {
        val nextScale = (scale * zoomChange).coerceIn(minScale, maxScale)
        if (nextScale <= minScale + 0.01f) {
            scale = minScale
            offset = Offset.Zero
            return
        }

        scale = nextScale
        if (nextScale < 1f) {
            offset = Offset.Zero
            return
        }
        offset = clampOffset(offset + panChange, nextScale)
    }

    fun onDrag(dragAmount: Offset) {
        if (scale <= 1f) return
        offset = clampOffset(offset + dragAmount, scale)
    }

    fun reset() {
        scale = minScale
        offset = Offset.Zero
    }

    /** Toggle between minScale and 1.0x for double-tap */
    fun toggleDesktopView() {
        if (minScale >= 1f) return // no desktop view when content fits
        if (scale < 1f - 0.01f) {
            // Currently zoomed out → snap to 1.0x
            scale = 1f
            offset = Offset.Zero
        } else {
            // Currently at 1.0x or zoomed in → snap to minScale
            scale = minScale
            offset = Offset.Zero
        }
    }

    private fun clampOffset(candidate: Offset, scale: Float): Offset {
        if (viewportSize == IntSize.Zero) return Offset.Zero
        if (kotlin.math.abs(scale - 1f) <= 0.01f) return Offset.Zero

        if (scale > 1f) {
            val maxX = viewportSize.width * (scale - 1f) / 2f
            val maxY = viewportSize.height * (scale - 1f) / 2f
            return Offset(
                x = candidate.x.coerceIn(-maxX, maxX),
                y = candidate.y.coerceIn(-maxY, maxY)
            )
        } else {
            // Shrunk: Y-axis pan only
            val maxY = viewportSize.height * (1f - scale) / 2f
            return Offset(
                x = 0f,
                y = candidate.y.coerceIn(-maxY, maxY)
            )
        }
    }
}

@Composable
fun rememberTerminalZoomState(): TerminalZoomState = remember { TerminalZoomState() }

@OptIn(ExperimentalFoundationApi::class)
fun Modifier.terminalZoom(zoomState: TerminalZoomState): Modifier = composed {
    val transformableState = rememberTransformableState { zoomChange, panChange, _ ->
        zoomState.onTransform(zoomChange, panChange)
    }

    this
        .onSizeChanged(zoomState::updateViewport)
        .layout { measurable, constraints ->
            if (zoomState.scale < 1f && zoomState.scale > 0f) {
                val invScale = 1f / zoomState.scale
                val expandedConstraints = constraints.copy(
                    maxWidth = (constraints.maxWidth * invScale).toInt(),
                    maxHeight = (constraints.maxHeight * invScale).toInt(),
                    minWidth = 0,
                    minHeight = 0
                )
                val placeable = measurable.measure(expandedConstraints)
                layout(constraints.maxWidth, constraints.maxHeight) {
                    placeable.place(0, 0)
                }
            } else {
                val placeable = measurable.measure(constraints)
                layout(placeable.width, placeable.height) {
                    placeable.place(0, 0)
                }
            }
        }
        .graphicsLayer {
            scaleX = zoomState.scale
            scaleY = zoomState.scale
            transformOrigin = if (zoomState.scale < 1f) {
                TransformOrigin(0f, 0f)
            } else {
                TransformOrigin.Center
            }
            translationX = if (zoomState.scale >= 1f) zoomState.offset.x else 0f
            translationY = if (zoomState.scale >= 1f) zoomState.offset.y else 0f
            clip = zoomState.scale > 1f
        }
        .transformable(
            state = transformableState,
            canPan = { zoomState.isZoomedIn }
        )
        .pointerInput(Unit) {
            detectTapGestures(
                onDoubleTap = { zoomState.toggleDesktopView() }
            )
        }
        .then(
            if (zoomState.isZoomedIn) {
                Modifier.pointerInput(zoomState.isZoomedIn) {
                    detectDragGestures { change, dragAmount ->
                        change.consume()
                        zoomState.onDrag(Offset(dragAmount.x, dragAmount.y))
                    }
                }
            } else {
                Modifier
            }
        )
}
