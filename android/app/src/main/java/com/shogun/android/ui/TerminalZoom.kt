package com.shogun.android.ui

import androidx.compose.foundation.gestures.detectDragGestures
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
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntSize

private const val MIN_TERMINAL_SCALE = 1f
private const val MAX_TERMINAL_SCALE = 3f

@Stable
class TerminalZoomState(
    private val minScale: Float = MIN_TERMINAL_SCALE,
    private val maxScale: Float = MAX_TERMINAL_SCALE
) {
    var scale by mutableFloatStateOf(minScale)
        private set

    var offset by mutableStateOf(Offset.Zero)
        private set

    private var viewportSize by mutableStateOf(IntSize.Zero)

    val isZoomed: Boolean
        get() = scale > minScale + 0.01f

    fun updateViewport(size: IntSize) {
        viewportSize = size
        offset = clampOffset(offset, scale)
    }

    fun onTransform(zoomChange: Float, panChange: Offset) {
        val nextScale = (scale * zoomChange).coerceIn(minScale, maxScale)
        if (nextScale <= minScale + 0.01f) {
            reset()
            return
        }

        scale = nextScale
        offset = clampOffset(offset + panChange, nextScale)
    }

    fun onDrag(dragAmount: Offset) {
        if (!isZoomed) return
        offset = clampOffset(offset + dragAmount, scale)
    }

    fun reset() {
        scale = minScale
        offset = Offset.Zero
    }

    private fun clampOffset(candidate: Offset, scale: Float): Offset {
        if (viewportSize == IntSize.Zero || scale <= minScale + 0.01f) {
            return Offset.Zero
        }

        val maxX = viewportSize.width * (scale - 1f) / 2f
        val maxY = viewportSize.height * (scale - 1f) / 2f
        return Offset(
            x = candidate.x.coerceIn(-maxX, maxX),
            y = candidate.y.coerceIn(-maxY, maxY)
        )
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
        .graphicsLayer {
            scaleX = zoomState.scale
            scaleY = zoomState.scale
            translationX = zoomState.offset.x
            translationY = zoomState.offset.y
            clip = true
        }
        .transformable(
            state = transformableState,
            canPan = { zoomState.isZoomed }
        )
        .then(
            if (zoomState.isZoomed) {
                Modifier.pointerInput(zoomState.isZoomed) {
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
