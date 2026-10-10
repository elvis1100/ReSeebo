package com.reseebo.reseebo

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.reseebo.reseebo.ocr.PaddleOcrChannel

class MainActivity : FlutterActivity() {
    private var paddleOcrChannel: PaddleOcrChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        paddleOcrChannel = PaddleOcrChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        paddleOcrChannel?.close()
        paddleOcrChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
