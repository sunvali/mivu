package com.yakov103.mivu.pip

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Decoded `pip-rig.json`: Pip's layered vector parts (design-system/mivu/characters/pip/rig/README.md). */
@Serializable
data class PipRigAsset(
    val version: Int,
    val artboard: Float,
    val ground: Float,
    val parallaxScale: Float = 0f,
    /** Artboard rectangles to fit, `[x, y, w, h]`. */
    val frames: Map<String, List<Float>>,
    val parts: List<Part>,
) {
    @Serializable
    data class Part(
        val id: String,
        val parent: String? = null,
        val pivot: List<Float>,
        val z: Int,
        val set: String? = null,
        val view: String? = null,
        val shape: String? = null,
        val visible: Boolean,
        val parallax: Float? = null,
        val fill: String,
        val fillDark: String? = null,
        val path: String,
        /** On a set's `body`: where the head views sit on it, `[k, tx, ty]` meaning head point × k + t. */
        val mount: List<Float>? = null,
    )

    companion object {
        const val MAX_BYTES = 1_048_576
        private val requiredPerView = listOf("head", "eye-l.open", "eye-r.open", "mouth.closedSmile")

        fun load(bytes: ByteArray): PipRigAsset {
            if (bytes.size > MAX_BYTES) throw PipRigError.TooLarge
            val asset = Json.decodeFromString<PipRigAsset>(bytes.decodeToString())
            if (asset.version != 2) throw PipRigError.Version
            require(asset.frames.values.all { it.size == 4 }) { "frame needs x y w h" }
            for (part in asset.parts) {
                require(part.pivot.size == 2 && (part.mount?.size ?: 3) == 3) { "bad pivot or mount on ${part.id}" }
                parsePath(part.path)
            }
            val ids = asset.parts.mapTo(HashSet()) { it.id }
            for (view in listOf("right", "front", "left")) {
                for (name in requiredPerView) if ("$name@$view" !in ids) throw PipRigError.MissingPart("$name@$view")
            }
            return asset
        }
    }
}

/** The id without its `@view` suffix; poses address parts by this name. */
val PipRigAsset.Part.name: String get() = id.substringBefore('@')

sealed class PipRigError(message: String) : Exception(message) {
    data object TooLarge : PipRigError("rig too large")
    data object Version : PipRigError("unsupported rig version")
    data class MissingPart(val id: String) : PipRigError("missing part $id")
    data class BadPath(val path: String) : PipRigError("bad path")
}

sealed interface PathOp {
    data class MoveTo(val x: Float, val y: Float) : PathOp
    data class LineTo(val x: Float, val y: Float) : PathOp
    data class CubicTo(val x1: Float, val y1: Float, val x2: Float, val y2: Float, val x: Float, val y: Float) : PathOp
    data class QuadTo(val x1: Float, val y1: Float, val x: Float, val y: Float) : PathOp
    data object Close : PathOp
}

/** Parses absolute `M L C Q Z` commands, the only ones the rig build emits; separators are `, \n\t`. */
fun parsePath(svg: String): List<PathOp> {
    val ops = ArrayList<PathOp>()
    var i = 0
    fun skip() { while (i < svg.length && svg[i] in ", \n\t") i++ }
    fun numbers(count: Int) = FloatArray(count) {
        skip()
        // A plain scan, not a Regex: Android's ICU regex is far too slow for the rig's ~60k numbers.
        val start = i
        if (i < svg.length && svg[i] in "+-") i++
        while (i < svg.length && (svg[i].isDigit() || svg[i] == '.')) i++
        if (i < svg.length && svg[i] in "eE") {
            i++
            if (i < svg.length && svg[i] in "+-") i++
            while (i < svg.length && svg[i].isDigit()) i++
        }
        svg.substring(start, i).toFloatOrNull() ?: throw PipRigError.BadPath(svg)
    }
    while (true) {
        skip()
        if (i == svg.length) return ops
        val p = when (svg[i++]) {
            'M' -> numbers(2).let { PathOp.MoveTo(it[0], it[1]) }
            'L' -> numbers(2).let { PathOp.LineTo(it[0], it[1]) }
            'C' -> numbers(6).let { PathOp.CubicTo(it[0], it[1], it[2], it[3], it[4], it[5]) }
            'Q' -> numbers(4).let { PathOp.QuadTo(it[0], it[1], it[2], it[3]) }
            'Z' -> PathOp.Close
            else -> throw PipRigError.BadPath(svg)
        }
        ops += p
    }
}

/** Tight curve bounds `[minX, minY, maxX, maxY]`, excluding control points, like CG's `boundingBoxOfPath`. */
fun pathBounds(ops: List<PathOp>): FloatArray {
    val b = floatArrayOf(Float.MAX_VALUE, Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE)
    fun add(x: Float, y: Float) { b[0] = minOf(b[0], x); b[1] = minOf(b[1], y); b[2] = maxOf(b[2], x); b[3] = maxOf(b[3], y) }
    var x0 = 0f
    var y0 = 0f
    var startX = 0f
    var startY = 0f
    for (op in ops) {
        when (op) {
            is PathOp.MoveTo -> { add(op.x, op.y); x0 = op.x; y0 = op.y; startX = op.x; startY = op.y }
            is PathOp.LineTo -> { add(op.x, op.y); x0 = op.x; y0 = op.y }
            is PathOp.QuadTo -> {
                add(op.x, op.y)
                // Each axis peaks where the derivative (p1 - p0)(1 - t) + (p2 - p1)t is zero.
                for (t in listOf((x0 - op.x1) / (x0 - 2 * op.x1 + op.x), (y0 - op.y1) / (y0 - 2 * op.y1 + op.y))) {
                    if (t > 0f && t < 1f) {
                        val u = 1 - t
                        add(u * u * x0 + 2 * u * t * op.x1 + t * t * op.x, u * u * y0 + 2 * u * t * op.y1 + t * t * op.y)
                    }
                }
                x0 = op.x; y0 = op.y
            }
            is PathOp.CubicTo -> {
                add(op.x, op.y)
                for (t in cubicExtrema(x0, op.x1, op.x2, op.x) + cubicExtrema(y0, op.y1, op.y2, op.y)) {
                    val u = 1 - t
                    fun at(p0: Float, p1: Float, p2: Float, p3: Float) = u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
                    add(at(x0, op.x1, op.x2, op.x), at(y0, op.y1, op.y2, op.y))
                }
                x0 = op.x; y0 = op.y
            }
            PathOp.Close -> { x0 = startX; y0 = startY }
        }
    }
    return if (b[0] > b[2]) FloatArray(4) else b
}

/** Parameters in (0, 1) where one axis of a cubic turns: roots of a t² + b t + c, the derivative over 3. */
private fun cubicExtrema(p0: Float, p1: Float, p2: Float, p3: Float): List<Float> {
    val a = -p0 + 3 * p1 - 3 * p2 + p3
    val b = 2 * (p0 - 2 * p1 + p2)
    val c = p1 - p0
    val roots = if (kotlin.math.abs(a) < 1e-6f) {
        if (kotlin.math.abs(b) < 1e-6f) emptyList() else listOf(-c / b)
    } else {
        val disc = b * b - 4 * a * c
        if (disc < 0) emptyList() else kotlin.math.sqrt(disc).let { listOf((-b + it) / (2 * a), (-b - it) / (2 * a)) }
    }
    return roots.filter { it > 0f && it < 1f }
}
