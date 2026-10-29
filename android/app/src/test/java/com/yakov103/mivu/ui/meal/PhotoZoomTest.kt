package com.yakov103.mivu.ui.meal

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.IntSize
import com.yakov103.mivu.diary.PhotoRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PhotoZoomTest {
    private val size = IntSize(1000, 2000)

    /** Where the photo point that is at [focus] before zooming from [zoom] to [next] ends up on screen. */
    private fun landing(zoom: Float, offset: Offset, focus: Offset, next: Float): Offset {
        val (z, o) = photoZoom(zoom, offset, focus, next, size)
        return (focus - offset) / zoom * z + o
    }

    @Test fun zoomingAroundAPointKeepsThePhotoUnderTheFingers() {
        val focus = Offset(300f, -400f) // from the centre of the viewer
        assertEquals(2f, photoZoom(1f, Offset.Zero, focus, 2f, size).first, 0f)
        val landed = landing(1f, Offset.Zero, focus, 2f)
        assertEquals(focus.x, landed.x, 0.01f); assertEquals(focus.y, landed.y, 0.01f)
        val (zoom, offset) = photoZoom(1f, Offset.Zero, focus, 2f, size)
        val again = landing(zoom, offset, focus, 4f)
        assertEquals(focus.x, again.x, 0.01f); assertEquals(focus.y, again.y, 0.01f)
    }

    @Test fun zoomStaysBetween100And500PercentAndNeverPansPastTheEdge() {
        assertEquals(5f, photoZoom(1f, Offset.Zero, Offset(900f, 900f), 9f, size).first, 0f)
        val (zoom, offset) = photoZoom(2f, Offset.Zero, Offset(900f, 900f), 0.2f, size)
        assertEquals(1f, zoom, 0f)
        assertEquals(Offset.Zero, offset)
        assertEquals(Offset(-500f, 1000f), photoZoom(2f, Offset(-9999f, 9999f), Offset.Zero, 2f, size).second)
    }

    @Test fun timingIsShownOnlyWhenSet() {
        assertEquals("Before eating", PhotoRole.before.timing)
        assertEquals("After eating", PhotoRole.after.timing)
        assertNull(PhotoRole.unspecified.timing)
    }
}
