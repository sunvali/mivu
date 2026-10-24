package com.yakov103.mivu.pip

import android.os.PowerManager
import com.yakov103.mivu.pip.MotionPolicy.Playback
import org.junit.Assert.assertEquals
import org.junit.Test

class MotionPolicyTest {
    private fun playback(remove: Boolean = false, saver: Boolean = false, thermal: Int = PowerManager.THERMAL_STATUS_NONE, resumed: Boolean = true) =
        MotionPolicy.playback(remove, saver, thermal, resumed)

    @Test fun notResumedIsHidden() {
        assertEquals(Playback.Hidden, playback(resumed = false))
        assertEquals(Playback.Hidden, playback(remove = true, saver = true, resumed = false))
    }

    @Test fun removeAnimationsIsStatic() = assertEquals(Playback.StaticPose, playback(remove = true))

    @Test fun powerSaveIsStatic() = assertEquals(Playback.StaticPose, playback(saver = true))

    @Test fun severeThermalIsStatic() {
        assertEquals(Playback.Animated, playback(thermal = PowerManager.THERMAL_STATUS_MODERATE))
        assertEquals(Playback.StaticPose, playback(thermal = PowerManager.THERMAL_STATUS_SEVERE))
        assertEquals(Playback.StaticPose, playback(thermal = PowerManager.THERMAL_STATUS_SHUTDOWN))
    }

    @Test fun otherwiseAnimated() = assertEquals(Playback.Animated, playback())
}
