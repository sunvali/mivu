package com.yakov103.mivu.pip

/** A resting-or-moving description of Pip. Joint names address rig parts without their `@view` suffix. */
data class PipPose(
    val joints: Map<String, Joint> = emptyMap(),
    val eyes: EyeShape = EyeShape.open,
    val mouth: MouthShape = MouthShape.closedSmile,
    /** Unit-disc pupil direction; +y looks down. */
    val gazeX: Float = 0f,
    val gazeY: Float = 0f,
    val blush: Boolean = false,
    /** How many of the rig's `heart-1…3` parts are visible. */
    val hearts: Int = 0,
    /** Today rests standing; Coach chooses `seated` explicitly. */
    val set: BodySet = BodySet.standing,
    /** -1 left, 0 front, +1 right. Small moves around a view slide features; larger ones swap views. */
    val headTurn: Float = 1f,
) {
    /** Rotation in radians, positive clockwise on screen; scale then offset are applied about the part's pivot. */
    data class Joint(
        val rotation: Float = 0f,
        val offsetX: Float = 0f,
        val offsetY: Float = 0f,
        val scaleX: Float = 1f,
        val scaleY: Float = 1f,
    )

    @Suppress("EnumEntryName") enum class EyeShape { open, half, closedHappy, closedSleepy, wide, heart }
    @Suppress("EnumEntryName") enum class MouthShape { closedSmile, smallOpen, bigOpen, o, concerned, yawn }
    @Suppress("EnumEntryName") enum class BodySet { standing, seated, curled }
}
