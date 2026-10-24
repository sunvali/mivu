package com.yakov103.mivu.pip

import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/** One frame's pose, resolved per part id: joints with gaze and parallax applied, what shows, and fades. */
data class PipResolved(
    val joints: Map<String, PipPose.Joint>,
    val visible: Set<String>,
    /** Only for the parts that fade (blush and hearts); every other part is opaque. */
    val alpha: Map<String, Float>,
    val set: PipPose.BodySet,
)

/** One shape to fill: `matrix` is `[a, b, c, d, tx, ty]` in artboard space; `clip` is the path it is masked to. */
data class PipDraw(
    val partID: String,
    val matrix: FloatArray,
    val fill: String,
    val fillDark: String?,
    val alpha: Float,
    val clip: PipDraw?,
)

/**
 * Pip's part tree, ported from iOS `PipRigView` (`build`, `apply`, `joint(of:)`) without any drawing: [resolve] turns a
 * pose into per-part state and [draw] flattens the tree into back-to-front fills, so both are JVM-testable.
 * [bounds] gives a part's tight path bounds `[minX, minY, maxX, maxY]`; gaze reach is measured from them.
 */
class PipRigScene(
    val asset: PipRigAsset,
    bounds: ((partID: String) -> FloatArray)? = null,
) {
    /** Each part's parsed path, shared by bounds and every renderer of this scene. */
    val pathOps: Map<String, List<PathOp>> = asset.parts.associate { it.id to parsePath(it.path) }
    private val bounds = bounds ?: { id -> pathBounds(pathOps.getValue(id)) }
    /** Part id -> its index in `asset.parts`, which every per-frame array ([PipFrame]) uses. */
    val index: Map<String, Int> = asset.parts.withIndex().associate { it.value.id to it.index }
    private val n = asset.parts.size
    /** Light and dark fills as ARGB, parsed once here so drawing never parses or throws. */
    private val fills = IntArray(n) { argb(asset.parts[it].fill) }
    private val darkFills = IntArray(n) { argb(asset.parts[it].fillDark ?: asset.parts[it].fill) }

    fun fill(partID: String, dark: Boolean): Int = fill(index.getValue(partID), dark)
    fun fill(part: Int, dark: Boolean): Int = if (dark) darkFills[part] else fills[part]

    private sealed interface Item { val z: Int }
    private class Shape(val part: Int, override val z: Int) : Item
    private class Node(val part: Int, override val z: Int) : Item
    private class Mount(override val z: Int) : Item

    private val byID = asset.parts.associateBy { it.id }
    /** Back-to-front items per node: part indices, then [root] and [mount]. Arrays, so a frame walks them without iterators. */
    private val order: Array<Array<Item>>
    private val root = n
    private val mount = n + 1
    /** Iris index -> its eye white's index (the clip), else -1. */
    private val clipOf = IntArray(n) { -1 }
    /** Per set ordinal: that set's `body` index, else -1 (the head then mounts on the root). */
    private val bodyOf = IntArray(PipPose.BodySet.entries.size) { -1 }
    /** Per body index: its head mount `[k, 0, 0, k, tx, ty]`. */
    private val mountMatrix = arrayOfNulls<FloatArray>(n)
    private val slots = HashMap<String, String>()
    /** Iris id -> how far the whole iris may travel inside the eye white at full gaze (x, y). */
    private val irisReach = HashMap<String, FloatArray>()
    /** Glint id -> its iris; the glint counter-shifts so the light seems fixed. */
    private val glintIris = HashMap<String, String>()
    /** Pupil id -> (loX, loY, hiX, hiY) travel inside its iris. */
    private val pupilReach = HashMap<String, FloatArray>()

    init {
        val children = LinkedHashMap<String, MutableList<Item>>()
        for ((i, part) in asset.parts.withIndex()) children.getOrPut(part.id) { mutableListOf() }.add(Shape(i, part.z))
        val mount = Mount(asset.parts.filter(::ridesHeadMount).minOfOrNull { it.z } ?: 0)
        for ((i, part) in asset.parts.withIndex()) {
            // Shared parts on `body` ride the head mount; a missing parent means root.
            val host = if (ridesHeadMount(part)) MOUNT else part.parent?.takeIf { it in byID } ?: ROOT
            children.getOrPut(host) { mutableListOf() }.add(Node(i, part.z))
            whiteOf(part)?.let { white ->
                clipOf[i] = index.getValue(white.id)
                val box = bounds(white.id)
                irisReach[part.id] = floatArrayOf(0.3f * (box[2] - box[0]), 0.4f * (box[3] - box[1]))
            }
            val parent = part.parent?.let(byID::get)
            if ("glint" in part.name && parent != null && "iris" in parent.name) glintIris[part.id] = parent.id
            var ancestor: PipRigAsset.Part? = part
            while (ancestor != null && ancestor.shape == null) ancestor = ancestor.parent?.let(byID::get)
            ancestor?.shape?.let { slots[part.id] = it }
            if ("pupil" in part.name && parent != null) {
                val iris = bounds(parent.id)
                val pupil = bounds(part.id)
                // Up to 35% of the iris radius, never past the iris edge.
                val reach = 0.35f * (iris[2] - iris[0]) / 2
                pupilReach[part.id] = floatArrayOf(
                    minOf(0f, maxOf(-reach, iris[0] - pupil[0])), minOf(0f, maxOf(-reach, iris[1] - pupil[1])),
                    maxOf(0f, minOf(reach, iris[2] - pupil[2])), maxOf(0f, minOf(reach, iris[3] - pupil[3])),
                )
            }
        }
        // The head mount lands on whichever set's body is active, or on the root when that set has none.
        for ((i, part) in asset.parts.withIndex()) if (part.name == "body" && part.set != null) {
            children.getValue(part.id).add(mount)
            PipPose.BodySet.entries.firstOrNull { it.name == part.set }?.let { bodyOf[it.ordinal] = i }
            val m = part.mount ?: listOf(1f, 0f, 0f)
            mountMatrix[i] = floatArrayOf(m[0], 0f, 0f, m[0], m[1], m[2])
        }
        children.getOrPut(ROOT) { mutableListOf() }.add(mount)
        // Stable, so equal z keeps insertion order like sibling CALayers: own shape, children, then the mount.
        order = Array(n + 2) { node ->
            val key = when (node) { root -> ROOT; this.mount -> MOUNT; else -> asset.parts[node].id }
            children[key].orEmpty().sortedBy { it.z }.toTypedArray()
        }
    }

    /** The shape slot (`eye-l.open`, `mouth.yawn`) a part belongs to, through its ancestors; null for always-on parts. */
    fun slot(partID: String): String? = slots[partID]

    /** Irises, pupils and glints follow the gaze; they saccade instead of springing like the body. */
    fun followsGaze(partID: String): Boolean = partID in irisReach || partID in pupilReach || partID in glintIris

    fun resolve(pose: PipPose): PipResolved {
        val (view, slide) = viewFor(pose.headTurn)
        val wanted = setOf("eye-l.${pose.eyes}", "eye-r.${pose.eyes}", "mouth.${pose.mouth}")
        val length = hypot(pose.gazeX, pose.gazeY)
        val gx = if (length > 1) pose.gazeX / length else pose.gazeX
        val gy = if (length > 1) pose.gazeY / length else pose.gazeY
        val joints = HashMap<String, PipPose.Joint>(asset.parts.size * 2)
        val visible = HashSet<String>()
        val alpha = HashMap<String, Float>()
        for (part in asset.parts) {
            val fade = alphaOf(part, pose)
            if (fade != null) alpha[part.id] = fade
            if (isShown(part, view, wanted, pose, fade)) visible += part.id
            // A joint keyed by the full id (`arm-r@seated`) moves only that set's part; a plain name moves every set's.
            val joint = pose.joints[part.id] ?: pose.joints[part.name] ?: REST
            var x = joint.offsetX
            var y = joint.offsetY
            pupilReach[part.id]?.let { r ->
                x += gx * (if (gx < 0) -r[0] else r[2])
                y += gy * (if (gy < 0) -r[1] else r[3])
            }
            val iris = irisReach[part.id]
            if (iris != null) {
                x += gx * iris[0]
                y += gy * iris[1]
            } else glintIris[part.id]?.let(irisReach::get)?.let { r ->
                x -= 0.3f * gx * r[0]
                y -= 0.3f * gy * r[1]
            }
            x += (part.parallax ?: 0f) * slide * asset.parallaxScale
            joints[part.id] = if (x == joint.offsetX && y == joint.offsetY) joint else joint.copy(offsetX = x, offsetY = y)
        }
        return PipResolved(joints, visible, alpha, pose.set)
    }

    /** A fresh frame holding [state]: one array slot per part, rendered and ready to draw. */
    fun frame(state: PipResolved, scaleYAdd: Map<String, Float> = emptyMap()): PipFrame {
        val f = PipFrame(this)
        for ((i, part) in asset.parts.withIndex()) {
            val j = state.joints[part.id] ?: REST
            f.joints[i * 5] = j.rotation; f.joints[i * 5 + 1] = j.offsetX; f.joints[i * 5 + 2] = j.offsetY
            f.joints[i * 5 + 3] = j.scaleX; f.joints[i * 5 + 4] = j.scaleY
            f.visible[i] = part.id in state.visible
            f.alpha[i] = state.alpha[part.id] ?: 1f
            f.scaleYAdd[i] = scaleYAdd[part.id] ?: scaleYAdd[part.name] ?: 0f
        }
        f.set = state.set
        render(f)
        return f
    }

    /** Back-to-front fills. [scaleYAdd] adds to a part's y scale by id or name (the additive breath on head and chest). */
    fun draw(state: PipResolved, scaleYAdd: Map<String, Float> = emptyMap()): List<PipDraw> = frame(state, scaleYAdd).let { f ->
        List(f.count) { k ->
            val i = f.drawPart[k]
            val part = asset.parts[i]
            val clip = f.clipPart[k].takeIf { it >= 0 }?.let {
                PipDraw(asset.parts[it].id, f.world.copyOfRange(f.clipSlot[k] * 6, f.clipSlot[k] * 6 + 6), asset.parts[it].fill, asset.parts[it].fillDark, 1f, null)
            }
            PipDraw(part.id, f.world.copyOfRange(i * 6, i * 6 + 6), part.fill, part.fillDark, f.drawAlpha[k], clip)
        }
    }

    /**
     * Flattens [f]'s per-part state into its draw list without allocating: each node's world matrix lands in its own
     * `world` slot, and each fill records its part, alpha and clip (the eye white in the iris's parent space).
     */
    fun render(f: PipFrame) {
        f.count = 0
        IDENTITY.copyInto(f.world, root * 6)
        items(f, root, root, 1f, -1, -1, -1, bodyOf[f.set.ordinal])
    }

    private fun items(f: PipFrame, node: Int, slot: Int, alpha: Float, clip: Int, clipSlot: Int, owner: Int, body: Int) {
        val list = order[node]
        for (k in list.indices) when (val item = list[k]) {
            is Shape -> {
                val c = f.count++
                f.drawPart[c] = item.part; f.drawAlpha[c] = alpha; f.clipPart[c] = clip; f.clipSlot[c] = clipSlot
            }
            is Node -> node(f, item.part, slot, alpha, clip, clipSlot, body)
            is Mount -> if (owner == body) {
                concatInto(f.world, slot * 6, if (owner < 0) IDENTITY else mountMatrix[owner]!!, 0, f.world, mount * 6)
                items(f, mount, mount, alpha, clip, clipSlot, -1, body)
            }
        }
    }

    private fun node(f: PipFrame, i: Int, parentSlot: Int, parentAlpha: Float, parentClip: Int, parentClipSlot: Int, body: Int) {
        if (!f.visible[i]) return // a hidden container hides its whole subtree
        val alpha = parentAlpha * f.alpha[i]
        if (alpha <= 0f) return
        val j = f.joints
        val pivot = asset.parts[i].pivot
        jointInto(pivot[0], pivot[1], j[i * 5], j[i * 5 + 1], j[i * 5 + 2], j[i * 5 + 3], j[i * 5 + 4] + f.scaleYAdd[i], f.scratch)
        concatInto(f.world, parentSlot * 6, f.scratch, 0, f.world, i * 6)
        // The iris travels freely inside a fixed wrapper masked to the eye white, in the parent's space.
        val clip = clipOf[i]
        if (clip >= 0) items(f, i, i, alpha, clip, parentSlot, i, body) else items(f, i, i, alpha, parentClip, parentClipSlot, i, body)
    }

    private fun ridesHeadMount(part: PipRigAsset.Part) = part.parent == "body" && part.set == null

    /** The eye white beside an iris (`eye-l`, or `eye-l.wide.white` for the other shapes). */
    private fun whiteOf(part: PipRigAsset.Part): PipRigAsset.Part? {
        if ("iris" !in part.name) return null
        return asset.parts.firstOrNull {
            it.parent == part.parent && (it.name.endsWith(".white") || it.name == "eye-l" || it.name == "eye-r")
        }
    }

    /** Blush and hearts fade instead of popping; null means the part has no fade. Progress props are out of scope. */
    private fun alphaOf(part: PipRigAsset.Part, pose: PipPose): Float? {
        if (part.name.startsWith("cheek-blush")) return if (pose.blush) 1f else 0f
        if (part.name.startsWith("heart-")) part.name.drop(6).toIntOrNull()?.let { return if (it <= pose.hearts) 1f else 0f }
        return null
    }

    private fun isShown(part: PipRigAsset.Part, view: String, wanted: Set<String>, pose: PipPose, fade: Float?): Boolean {
        if (part.view != null && part.view != view) return false
        if (part.set != null && part.set != pose.set.name) return false
        slots[part.id]?.let { return it in wanted }
        return part.visible || fade != null
    }

    companion object {
        /** `#RRGGBB` as opaque ARGB; anything unparsable is black, as on iOS. */
        fun argb(hex: String): Int = ((hex.drop(1).toLongOrNull(16) ?: 0L).toInt() and 0xFFFFFF) or (0xFF shl 24)

        private const val ROOT = "@root"
        private const val MOUNT = "@mount"
        internal val REST = PipPose.Joint()
        private val IDENTITY = floatArrayOf(1f, 0f, 0f, 1f, 0f, 0f)

        /** Which head view to show and how far (-1...1) to slide features inside it. */
        fun viewFor(turn: Float): Pair<String, Float> {
            val (name, centre, span) = when {
                turn > 0.35f -> Triple("right", 1f, 0.65f)
                turn < -0.35f -> Triple("left", -1f, 0.65f)
                else -> Triple("front", 0f, 0.35f)
            }
            return name to ((turn - centre) / span).coerceIn(-1f, 1f)
        }
    }
}

/** A part's local transform about its pivot: `p' = pivot + offset + S·R·(p − pivot)`, rotation clockwise in y-down. */
fun jointMatrix(pivotX: Float, pivotY: Float, joint: PipPose.Joint): FloatArray = FloatArray(6).also {
    jointInto(pivotX, pivotY, joint.rotation, joint.offsetX, joint.offsetY, joint.scaleX, joint.scaleY, it)
}

internal fun jointInto(pivotX: Float, pivotY: Float, rotation: Float, x: Float, y: Float, scaleX: Float, scaleY: Float, out: FloatArray) {
    val cos = cos(rotation)
    val sin = sin(rotation)
    val a = scaleX * cos
    val c = -scaleX * sin
    val b = scaleY * sin
    val d = scaleY * cos
    out[0] = a; out[1] = b; out[2] = c; out[3] = d
    out[4] = pivotX + x - (a * pivotX + c * pivotY); out[5] = pivotY + y - (b * pivotX + d * pivotY)
}

/** `m ∘ n`: applies [n], then [m]. */
fun concat(m: FloatArray, n: FloatArray) = FloatArray(6).also { concatInto(m, 0, n, 0, it, 0) }

/** `m ∘ n` written into [out] at [oo]; [out] may be [m] or [n] only at a different offset. */
internal fun concatInto(m: FloatArray, mo: Int, n: FloatArray, no: Int, out: FloatArray, oo: Int) {
    val m0 = m[mo]; val m1 = m[mo + 1]; val m2 = m[mo + 2]; val m3 = m[mo + 3]; val m4 = m[mo + 4]; val m5 = m[mo + 5]
    val n0 = n[no]; val n1 = n[no + 1]; val n2 = n[no + 2]; val n3 = n[no + 3]; val n4 = n[no + 4]; val n5 = n[no + 5]
    out[oo] = m0 * n0 + m2 * n1; out[oo + 1] = m1 * n0 + m3 * n1
    out[oo + 2] = m0 * n2 + m2 * n3; out[oo + 3] = m1 * n2 + m3 * n3
    out[oo + 4] = m0 * n4 + m2 * n5 + m4; out[oo + 5] = m1 * n4 + m3 * n5 + m5
}

fun mapPoint(m: FloatArray, x: Float, y: Float) = floatArrayOf(m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5])

/**
 * One frame's per-part state, indexed by [PipRigScene.index] and reused across frames: joints as
 * `[rotation, offsetX, offsetY, scaleX, scaleY]` per part, what shows, fades and the additive breath. [PipRigScene.render]
 * writes the draw list: `count` fills of `drawPart` (world matrix at `world[part * 6]`), alpha, and clip part and slot.
 */
class PipFrame(val scene: PipRigScene) {
    private val n = scene.asset.parts.size
    val joints = FloatArray(n * 5).also { for (i in 0 until n) { it[i * 5 + 3] = 1f; it[i * 5 + 4] = 1f } }
    val visible = BooleanArray(n)
    val alpha = FloatArray(n) { 1f }
    val scaleYAdd = FloatArray(n)
    var set = PipPose.BodySet.standing
    /** World matrices `[a, b, c, d, tx, ty]`: one per part, then the root and the head mount. */
    val world = FloatArray((n + 2) * 6)
    var count = 0
    val drawPart = IntArray(n)
    val drawAlpha = FloatArray(n)
    /** The clip's part index (-1 for none) and the world slot its path is drawn in. */
    val clipPart = IntArray(n)
    val clipSlot = IntArray(n)
    internal val scratch = FloatArray(6)

    private fun at(id: String) = scene.index.getValue(id)
    fun joint(id: String) = at(id).let { PipPose.Joint(joints[it * 5], joints[it * 5 + 1], joints[it * 5 + 2], joints[it * 5 + 3], joints[it * 5 + 4]) }
    fun isVisible(id: String) = visible[at(id)]
    fun scaleYAdd(id: String) = scaleYAdd[at(id)]
}
