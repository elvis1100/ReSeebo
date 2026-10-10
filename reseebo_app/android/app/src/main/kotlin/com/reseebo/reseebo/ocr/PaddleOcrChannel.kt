package com.reseebo.reseebo.ocr

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** One mutex covers inference, engine switching and teardown across all calls. */
class PaddleOcrChannel(context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "reseebo/ocr")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mutex = Mutex()
    private val session = PaddleEngineSession(context.applicationContext)
    private var closed = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method !in listOf("recognize", "release", "engines", "assetSha256")) {
                result.notImplemented()
            } else {
                scope.launch {
                    try {
                        val response = mutex.withLock {
                            if (closed) throw PaddleChannelError("closed", "OCR channel is closed")
                            when (call.method) {
                                "release" -> { session.release(); null }
                                "engines" -> session.descriptors()
                                "assetSha256" -> session.assetSha256(call.argument<String>("path") ?: "")
                                else -> {
                                    val engineId = call.argument<String>("engineId")
                                    val imagePath = call.argument<String>("imagePath")
                                    if (engineId.isNullOrBlank() || imagePath.isNullOrBlank()) {
                                        throw PaddleChannelError("invalid_arguments", "engineId and imagePath are required")
                                    }
                                    session.recognize(engineId, imagePath)
                                }
                            }
                        }
                        result.success(response)
                    } catch (error: PaddleChannelError) {
                        result.error(error.code, error.message, null)
                    } catch (error: Throwable) {
                        result.error("native_inference", error.message ?: error.javaClass.name, null)
                    }
                }
            }
        }
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        scope.launch {
            try { mutex.withLock { session.release() } } finally { scope.cancel() }
        }
    }
}
