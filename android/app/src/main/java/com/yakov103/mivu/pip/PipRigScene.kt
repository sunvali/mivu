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

    private sealed interface Item { val z: Int }
    private class Shape(val part: PipRigAsset.Part) : Item { override val z = part.z }
    private class Node(val part: PipRigAsset.Part) : Item { override val z = part.z }
    private class Mount(override val z: Int) : Item

    private val byID = asset.parts.associateBy { it.id }
    /** Back-to-front items per node id; [ROOT] and [MOUNT] are the root and the head mount. */
    private val order = HashMap<String, List<Item>>()
    private val slots = HashMap<String, String>()
    private val irisWhite = HashMap<String, PipRigAsset.Part>()
    /** Iris id -> how far the whole iris may travel inside the eye white at full gaze (x, y). */
    private val irisReach = HashMap<String, FloatArray>()
    /** Glint id -> its iris; the glint counter-shifts so the light seems fixed. */
    private val glintIris = HashMap<String, String>()
    /** Pupil id -> (loX, loY, hiX, hiY) travel inside its iris. */
    private val pupilReach = HashMap<String, FloatArray>()

    init {
        val children = LinkedHashMap<String, MutableList<Item>>()
        for (part in asset.parts) children.getOrPut(part.id) { mutableListOf() }.add(Shape(part))
        val mount = Mount(asset.parts.filter(::ridesHeadMount).minOfOrNull { it.z } ?: 0)
        for (part in asset.parts) {
            // Shared parts on `body` ride the head mount; a missing parent means root.
            val host = if (ridesHeadMount(part)) MOUNT else part.parent?.takeIf { it in byID } ?: ROOT
            children.getOrPut(host) { mutableListOf() }.add(Node(part))
            whiteOf(part)?.let { white ->
                irisWhite[part.id] = white
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
        for (part in asset.parts) if (part.name == "body" && part.set != null) children.getValue(part.id).add(mount)
        children.getOrPut(ROOT) { mutableListOf() }.add(mount)
        // Stable, so equal z keeps insertion order like sibling CALayers: own shape, children, then the mount.
        for ((id, items) in children) order[id] = items.sortedBy { it.z }
    }

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

    /** Back-to-front fills. [scaleYAdd] adds to a part's y scale by id or name (the additive breath on head and chest). */
    fun draw(state: PipResolved, scaleYAdd: Map<String, Float> = emptyMap()): List<PipDraw> {
        val body = asset.parts.firstOrNull { it.name == "body" && it.set == state.set.name }
        return Frame(state, scaleYAdd, body).apply { items(ROOT, IDENTITY, 1f, null, null) }.out
    }

    private inner class Frame(val state: PipResolved, val scaleYAdd: Map<String, Float>, val body: PipRigAsset.Part?) {
        val out = ArrayList<PipDraw>()

        fun items(id: String, world: FloatArray, alpha: Float, clip: PipDraw?, owner: PipRigAsset.Part?) {
            for (item in order[id].orEmpty()) when (item) {
                is Shape -> out += PipDraw(item.part.id, world, item.part.fill, item.part.fillDark, alpha, clip)
                is Node -> node(item.part, world, alpha, clip)
                is Mount -> if (owner == body) {
                    val m = owner?.mount ?: listOf(1f, 0f, 0f)
                    items(MOUNT, concat(world, floatArrayOf(m[0], 0f, 0f, m[0], m[1], m[2])), alpha, clip, null)
                }
            }
        }

        fun node(part: PipRigAsset.Part, parentWorld: FloatArray, parentAlpha: Float, parentClip: PipDraw?) {
            if (part.id !in state.visible) return // a hidden container hides its whole subtree
            val alpha = parentAlpha * (state.alpha[part.id] ?: 1f)
            if (alpha <= 0f) return
            var joint = state.joints[part.id] ?: REST
            val add = scaleYAdd[part.id] ?: scaleYAdd[part.name]
            if (add != null) joint = joint.copy(scaleY = joint.scaleY + add)
            // The iris travels freely inside a fixed wrapper masked to the eye white, in the parent's space.
            val clip = irisWhite[part.id]?.let { PipDraw(it.id, parentWorld, it.fill, it.fillDark, 1f, null) } ?: parentClip
            items(part.id, concat(parentWorld, jointMatrix(part.pivot[0], part.pivot[1], joint)), alpha, clip, part)
        }
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
        private const val ROOT = "@root"
        private const val MOUNT = "@mount"
        private val REST = PipPose.Joint()
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
fun jointMatrix(pivotX: Float, pivotY: Float, joint: PipPose.Joint): FloatArray {
    val cos = cos(joint.rotation)
    val sin = sin(joint.rotation)
    val a = joint.scaleX * cos
    val c = -joint.scaleX * sin
    val b = joint.scaleY * sin
    val d = joint.scaleY * cos
    return floatArrayOf(a, b, c, d, pivotX + joint.offsetX - (a * pivotX + c * pivotY), pivotY + joint.offsetY - (b * pivotX + d * pivotY))
}

/** `m ∘ n`: applies [n], then [m]. */
fun concat(m: FloatArray, n: FloatArray) = floatArrayOf(
    m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1],
    m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3],
    m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5],
)

fun mapPoint(m: FloatArray, x: Float, y: Float) = floatArrayOf(m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5])
