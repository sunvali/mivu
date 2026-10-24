package com.yakov103.mivu.pip

import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.semantics.clearAndSetSemantics

/**
 * Draws a rendered [PipFrame] (from [PipMotion.sample] or [PipRigScene.frame]), fitting `asset.frames[frame]` (the whole
 * artboard when null). [state] is read in the draw phase only, so animating it redraws without recomposing. Paths,
 * matrices and the paint are reused, so a frame draws without allocating. Only the bottom edge crops: Pip peeks over the
 * bar, while head turns and tilts may spill past the other edges. Pip is decorative and hidden from accessibility.
 */
@Composable
fun PipRig(scene: PipRigScene, state: () -> PipFrame, dark: Boolean, frame: String?, modifier: Modifier = Modifier) {
    val paths = remember(scene) { Array(scene.asset.parts.size) { path(scene.pathOps.getValue(scene.asset.parts[it].id)) } }
    val tools = remember { Tools() }
    val rect = scene.asset.frames[frame] ?: listOf(0f, 0f, scene.asset.artboard, scene.asset.artboard)
    // Its own layer, so an animating Pip re-records only itself, never the screen around it.
    Canvas(modifier.graphicsLayer().clearAndSetSemantics {}) {
        val s = minOf(size.width / rect[2], size.height / rect[3])
        val tx = (size.width - rect[2] * s) / 2 - rect[0] * s
        val ty = (size.height - rect[3] * s) / 2 - rect[1] * s
        clipRect(-size.width, -size.height, size.width * 2, size.height) {
            drawIntoCanvas { canvas ->
                val c = canvas.nativeCanvas
                val f = state()
                c.save()
                c.translate(tx, ty)
                c.scale(s, s)
                for (k in 0 until f.count) {
                    val i = f.drawPart[k]
                    val clip = f.clipPart[k]
                    c.save()
                    if (clip >= 0) {
                        tools.set(tools.matrix, f.world, f.clipSlot[k] * 6)
                        c.concat(tools.matrix)
                        c.clipPath(paths[clip])
                        tools.matrix.invert(tools.inverse)
                        c.concat(tools.inverse)
                    }
                    tools.set(tools.matrix, f.world, i * 6)
                    c.concat(tools.matrix)
                    tools.paint.color = scene.fill(i, dark)
                    tools.paint.alpha = (f.drawAlpha[k] * 255 + 0.5f).toInt()
                    c.drawPath(paths[i], tools.paint)
                    c.restore()
                }
                c.restore()
            }
        }
    }
}

private class Tools {
    val matrix = Matrix()
    val inverse = Matrix()
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val values = FloatArray(9).also { it[8] = 1f }

    /** Writes the affine `[a, b, c, d, tx, ty]` at [o] into [m]. */
    fun set(m: Matrix, w: FloatArray, o: Int) {
        values[Matrix.MSCALE_X] = w[o]; values[Matrix.MSKEW_Y] = w[o + 1]
        values[Matrix.MSKEW_X] = w[o + 2]; values[Matrix.MSCALE_Y] = w[o + 3]
        values[Matrix.MTRANS_X] = w[o + 4]; values[Matrix.MTRANS_Y] = w[o + 5]
        m.setValues(values)
    }
}

internal fun path(ops: List<PathOp>) = Path().apply {
    for (op in ops) when (op) {
        is PathOp.MoveTo -> moveTo(op.x, op.y)
        is PathOp.LineTo -> lineTo(op.x, op.y)
        is PathOp.CubicTo -> cubicTo(op.x1, op.y1, op.x2, op.y2, op.x, op.y)
        is PathOp.QuadTo -> quadTo(op.x1, op.y1, op.x, op.y)
        PathOp.Close -> close()
    }
}
