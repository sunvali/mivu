package com.yakov103.mivu.pip

import android.os.PowerManager
import com.yakov103.mivu.pip.MotionPolicy.Playback
import org.junit.Assert.assertEquals
import org.junit.Test

/** iOS #69: only Remove animations and serious heat hold Pip still; Power Saver keeps him moving. */
class MotionPolicyTest {
    private fun playback(remove: Boolean = false, thermal: Int = PowerManager.THERMAL_STATUS_NONE, resumed: Boolean = true,
                         covered: Boolean = false) =
        MotionPolicy.playback(remove, thermal, resumed, covered)

    @Test fun notResumedIsHidden() {
        assertEquals(Playback.Hidden, playback(resumed = false))
        assertEquals(Playback.Hidden, playback(remove = true, resumed = false))
    }

    @Test fun removeAnimationsIsStatic() = assertEquals(Playback.StaticPose, playback(remove = true))

    @Test fun severeThermalIsStatic() {
        assertEquals(Playback.Animated, playback(thermal = PowerManager.THERMAL_STATUS_MODERATE))
        assertEquals(Playback.StaticPose, playback(thermal = PowerManager.THERMAL_STATUS_SEVERE))
        assertEquals(Playback.StaticPose, playback(thermal = PowerManager.THERMAL_STATUS_SHUTDOWN))
    }

    /** iOS: a sheet, picker or camera over the surface hides Pip, whatever the motion settings. */
    @Test fun coveredIsHidden() {
        assertEquals(Playback.Hidden, playback(covered = true))
        assertEquals(Playback.Hidden, playback(remove = true, covered = true))
    }

    @Test fun otherwiseAnimated() = assertEquals(Playback.Animated, playback())
}
