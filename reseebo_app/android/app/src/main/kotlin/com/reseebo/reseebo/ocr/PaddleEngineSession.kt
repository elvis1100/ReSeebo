package com.reseebo.reseebo.ocr

import android.content.Context
import android.graphics.BitmapFactory
import android.os.SystemClock
import com.paddle.ocr.EngineConfig
import com.paddle.ocr.PaddleOCR
import com.paddle.ocr.PaddleOCRConfig
import com.paddle.ocr.util.OpenCVUtils
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

class PaddleChannelError(val code: String, message: String) : Exception(message)

/** Caller must serialize recognize/release. Holds at most one heavy SDK session. */
class PaddleEngineSession(private val context: Context) {
    private var loadedId: String? = null
    private var session: PaddleOCR? = null
    private val verification = context.packageName == "com.reseebo.reseebo.verification"
    private val engines by lazy {
        val manifest = context.assets.open("flutter_assets/assets/ocr/model_manifest.json")
            .bufferedReader().use { JSONObject(it.readText()) }
        require(manifest.getInt("schemaVersion") == 1)
        val list = manifest.getJSONArray("engines")
        (0 until list.length()).map { list.getJSONObject(it) }.associateBy { it.getString("id") }
    }

    suspend fun descriptors(): List<Map<String, String>> = withContext(Dispatchers.IO) {
        engines.values.filter { verification || enabled(it) }.map { engine ->
            verifyArtifacts(engine)
            mapOf("engineId" to engine.getString("id"),
                "modelVersion" to engine.getString("modelVersion"),
                "runtimeVersion" to engine.getString("runtimeVersion"))
        }
    }

    private fun enabled(engine: JSONObject) =
        engine.optBoolean("available") && engine.optBoolean("verifiedOnDevice")

    suspend fun recognize(engineId: String, imagePath: String): Map<String, Any> =
        withContext(Dispatchers.IO) {
            val started = SystemClock.elapsedRealtime()
            val engine = engines[engineId]
                ?: throw PaddleChannelError("unsupported_engine", "Unsupported OCR engine: $engineId")
            if (!verification && !enabled(engine)) {
                throw PaddleChannelError("engine_unavailable", engine.getString("unavailableReason"))
            }
            val bytes = try { File(imagePath).readBytes() } catch (error: Exception) {
                throw PaddleChannelError("invalid_image", "Cannot read recognition input: ${error.message}")
            }
            // Decode encoded pixels without implicit EXIF rotation. The supplied
            // recognition image owns its orientation; bounds refer to its pixels.
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                ?: throw PaddleChannelError("invalid_image", "Recognition input is not a decodable image")
            try {
                if (loadedId != engineId) {
                    release()
                    verifyArtifacts(engine)
                    if (!OpenCVUtils.init(context)) {
                        throw PaddleChannelError("native_runtime", "Bundled OpenCV could not initialize")
                    }
                    val prefix = "flutter_assets/assets/ocr/$engineId"
                    // Detector YAML is pinned provenance, not applied configuration.
                    // Both engines use the SDK defaults (thresholds .3/.6, unclip 1.5);
                    // rec YAML supplies only its dictionary. Physical calibration
                    // must precede any tuning and a preprocessing identity update.
                    session = PaddleOCR.create(context, PaddleOCRConfig(), EngineConfig(),
                        "$prefix/det/inference.onnx", "$prefix/rec/inference.onnx",
                        "$prefix/rec/inference.yml")
                    loadedId = engineId
                }
                val result = session!!.recognize(bitmap)
                // SDK DBPostProcessor already inverts detector resizing and
                // preserves the detection quad when cropping for recognition.
                // Applying a second resize inversion here would corrupt bounds.
                val geometry = PaddleGeometry()
                val lines = result.results.map { line ->
                    val points = line.box.points.map {
                        geometry.toInput(it.x.toDouble(), it.y.toDouble(), bitmap.width, bitmap.height)
                    }
                    val left = points.minOf { it.first }
                    val top = points.minOf { it.second }
                    mapOf("text" to line.text, "left" to left, "top" to top,
                        "width" to points.maxOf { it.first } - left,
                        "height" to points.maxOf { it.second } - top)
                    // SDK has line quads, no word locations; tokens are omitted.
                }
                mapOf("engineId" to engineId, "modelVersion" to engine.getString("modelVersion"),
                    "runtimeVersion" to engine.getString("runtimeVersion"),
                    "elapsedMs" to SystemClock.elapsedRealtime() - started,
                    "imageWidth" to bitmap.width, "imageHeight" to bitmap.height, "lines" to lines)
            } catch (error: Throwable) {
                release()
                throw error
            } finally {
                bitmap.recycle()
            }
        }

    private fun verifyArtifacts(engine: JSONObject) {
        val artifacts = engine.getJSONArray("artifacts")
        for (index in 0 until artifacts.length()) {
            val artifact = artifacts.getJSONObject(index)
            val path = artifact.getString("path")
            val digest = MessageDigest.getInstance("SHA-256")
            try {
                context.assets.open("flutter_assets/$path").use { input ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        digest.update(buffer, 0, count)
                    }
                }
            } catch (error: Exception) {
                throw PaddleChannelError("missing_assets", "Missing bundled OCR artifact: $path")
            }
            val actual = digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
            if (actual != artifact.getString("sha256")) {
                throw PaddleChannelError("asset_integrity", "SHA-256 mismatch: $path")
            }
        }
    }

    suspend fun release() = withContext(Dispatchers.IO) {
        try { session?.release() } finally { session = null; loadedId = null }
    }
}
