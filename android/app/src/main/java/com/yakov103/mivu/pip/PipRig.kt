package com.yakov103.mivu.pip

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Matrix
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.semantics.clearAndSetSemantics

/**
 * Draws [scene] in [state]'s pose, fitting `asset.frames[frame]` (the whole artboard when null). [state] is read in the
 * draw phase only, so animating it redraws without recomposing. Only the bottom edge crops: Pip peeks over the bar,
 * while head turns and tilts may spill past the other edges. Pip is decorative and hidden from accessibility.
 */
@Composable
fun PipRig(scene: PipRigScene, state: () -> PipResolved, dark: Boolean, frame: String?, modifier: Modifier = Modifier) {
    val paths = remember(scene) { scene.pathOps.mapValues { composePath(it.value) } }
    val matrix = remember { Matrix() }
    val inverse = remember { Matrix() }
    val rect = scene.asset.frames[frame] ?: listOf(0f, 0f, scene.asset.artboard, scene.asset.artboard)
    Canvas(modifier.clearAndSetSemantics {}) {
        val s = minOf(size.width / rect[2], size.height / rect[3])
        val tx = (size.width - rect[2] * s) / 2 - rect[0] * s
        val ty = (size.height - rect[3] * s) / 2 - rect[1] * s
        clipRect(-size.width, -size.height, size.width * 2, size.height) {
            withTransform({ translate(tx, ty); scale(s, s, pivot = androidx.compose.ui.geometry.Offset.Zero) }) {
                for (d in scene.draw(state())) {
                    val color = Color(scene.fill(d.partID, dark))
                    val clip = d.clip
                    drawContext.canvas.save()
                    if (clip != null) {
                        drawContext.canvas.concat(matrix.set(clip.matrix))
                        drawContext.canvas.clipPath(paths.getValue(clip.partID))
                        inverse.set(clip.matrix).invert()
                        drawContext.canvas.concat(inverse)
                    }
                    drawContext.canvas.concat(matrix.set(d.matrix))
                    drawPath(paths.getValue(d.partID), color, alpha = d.alpha)
                    drawContext.canvas.restore()
                }
            }
        }
    }
}

/** Writes an affine `[a, b, c, d, tx, ty]` into this 4×4 (column-major) matrix. */
private fun Matrix.set(m: FloatArray): Matrix {
    reset()
    values[Matrix.ScaleX] = m[0]; values[Matrix.SkewY] = m[1]
    values[Matrix.SkewX] = m[2]; values[Matrix.ScaleY] = m[3]
    values[Matrix.TranslateX] = m[4]; values[Matrix.TranslateY] = m[5]
    return this
}

private fun composePath(ops: List<PathOp>) = Path().apply {
    for (op in ops) when (op) {
        is PathOp.MoveTo -> moveTo(op.x, op.y)
        is PathOp.LineTo -> lineTo(op.x, op.y)
        is PathOp.CubicTo -> cubicTo(op.x1, op.y1, op.x2, op.y2, op.x, op.y)
        is PathOp.QuadTo -> quadraticTo(op.x1, op.y1, op.x, op.y)
        PathOp.Close -> close()
    }
}
