package com.reseebo.reseebo.ocr

/** Inverts resize -> padding -> crop; returned positions are in input pixels. */
data class PaddleGeometry(
    val scaleX: Double = 1.0,
    val scaleY: Double = 1.0,
    val padX: Double = 0.0,
    val padY: Double = 0.0,
    val cropX: Double = 0.0,
    val cropY: Double = 0.0,
) {
    init {
        require(scaleX.isFinite() && scaleX > 0 && scaleY.isFinite() && scaleY > 0)
        require(listOf(padX, padY, cropX, cropY).all { it.isFinite() })
    }

    fun toInput(x: Double, y: Double, width: Int, height: Int): Pair<Double, Double> {
        require(width > 0 && height > 0 && x.isFinite() && y.isFinite())
        return Pair(
            ((x + cropX - padX) / scaleX).coerceIn(0.0, width.toDouble()),
            ((y + cropY - padY) / scaleY).coerceIn(0.0, height.toDouble()),
        )
    }
}
