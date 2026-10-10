package com.reseebo.reseebo.ocr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PaddleGeometryTest {
    @Test fun resizePadCropReturnsInputCoordinates() {
        // Input (100,200) becomes (63,113): half-size, then pad (20,30), crop (7,17).
        val transform = PaddleGeometry(scaleX = 0.5, scaleY = 0.5,
            padX = 20.0, padY = 30.0, cropX = 7.0, cropY = 17.0)
        val point = transform.toInput(63.0, 113.0, 640, 480)
        assertEquals(100.0, point.first, 1.0)
        assertEquals(200.0, point.second, 1.0)
    }

    @Test fun outOfImageCoordinatesAreClipped() {
        val transform = PaddleGeometry(scaleX = 0.5, scaleY = 0.5)
        val point = transform.toInput(-20.0, 1000.0, 640, 480)
        assertEquals(0.0, point.first, 0.0)
        assertEquals(480.0, point.second, 0.0)
        assertTrue(point.first in 0.0..640.0 && point.second in 0.0..480.0)
    }
}
