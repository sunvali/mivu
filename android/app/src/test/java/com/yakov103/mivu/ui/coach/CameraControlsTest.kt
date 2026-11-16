package com.yakov103.mivu.ui.coach

import androidx.camera.core.ImageCapture
import org.junit.Assert.assertEquals
import org.junit.Test

/** iOS CoachCameraSession.lensFactors / clampedZoom and CoachCameraControls zoomText / dial / flash cycle. */
class CameraControlsTest {
    @Test fun lensesFromRatios() {
        assertEquals(listOf(0.5f, 1f, 5f), lensZooms(listOf(1f, 0.5f, 5f, 1.0001f)))
        assertEquals(emptyList<Float>(), lensZooms(listOf(1f)))
        assertEquals(emptyList<Float>(), lensZooms(emptyList()))
    }

    @Test fun clampToTwiceLongestLens() = assertEquals(10f, clampedZoom(30f, listOf(0.5f, 1f, 5f), 0.5f, 30f))

    @Test fun clampRespectsCameraMax() = assertEquals(8f, clampedZoom(9f, listOf(0.5f, 1f, 5f), 0.5f, 8f))

    @Test fun clampWithoutLensesUsesCameraRange() {
        assertEquals(0.5f, clampedZoom(0.1f, emptyList(), 0.5f, 10f))
        assertEquals(10f, clampedZoom(20f, emptyList(), 0.5f, 10f))
    }

    @Test fun currentLensFollowsZoom() {
        assertEquals(1f, currentLens(2.9f, listOf(0.5f, 1f, 3f)))
        assertEquals(3f, currentLens(2.995f, listOf(0.5f, 1f, 3f)))
        assertEquals(0.5f, currentLens(0.4f, listOf(0.5f, 1f, 3f)))
    }

    @Test fun zoomLabels() {
        assertEquals("0.5", zoomText(0.5f))
        assertEquals("3", zoomText(3.02f))
        assertEquals("1.4", zoomText(1.36f))
    }

    @Test fun slideZoomIsRatio() {
        assertEquals(1f, slideZoom(2f, 90f), 0.001f)
        assertEquals(slideZoom(2f, 90f), slideZoom(slideZoom(2f, 30f), 60f), 0.001f)
    }

    @Test fun flashCycles() {
        assertEquals(ImageCapture.FLASH_MODE_ON, nextFlash(ImageCapture.FLASH_MODE_AUTO))
        assertEquals(ImageCapture.FLASH_MODE_OFF, nextFlash(ImageCapture.FLASH_MODE_ON))
        assertEquals(ImageCapture.FLASH_MODE_AUTO, nextFlash(ImageCapture.FLASH_MODE_OFF))
    }
}
