package com.example.vision_assistant

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.label.ImageLabeling
import com.google.mlkit.vision.label.ImageLabelerOptions
import com.google.mlkit.vision.objects.ObjectDetection
import com.google.mlkit.vision.objects.defaults.ObjectDetectorOptions
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.*
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

private const val TAG = "VisionPlugin"

/**
 * Flutter platform channel plugin — fully offline vision via ML Kit.
 *
 * Uses three ML Kit APIs (all bundled, zero runtime download required):
 *   • Image Labeling  — what things are in the scene
 *   • Object Detection — where detected objects are positioned
 *   • Text Recognition — any readable text in the frame
 *
 * The optional on-device LLM layer (previously MediaPipe Gemma) has been
 * removed from the native side.  The Dart layer (GemmaService / MlcInference)
 * gracefully handles [loadModel] returning false and continues to call
 * [analyzeImage], which always produces a real ML Kit description.
 */
class MlcLlmPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    private val workerThread = Dispatchers.IO.limitedParallelism(1)
    private val scope = CoroutineScope(workerThread + SupervisorJob())

    // ── ML Kit clients (lazy, reused) ─────────────────────────────────────

    private val labeler by lazy {
        ImageLabeling.getClient(
            ImageLabelerOptions.Builder().setConfidenceThreshold(0.60f).build()
        )
    }

    private val objectDetector by lazy {
        ObjectDetection.getClient(
            ObjectDetectorOptions.Builder()
                .setDetectorMode(ObjectDetectorOptions.SINGLE_IMAGE_MODE)
                .enableMultipleObjects()
                .enableClassification()
                .build()
        )
    }

    private val textRecognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    // ── FlutterPlugin lifecycle ───────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "mlc_llm_channel")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    // ── Method dispatch ───────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "loadModel" -> {
                // LLM loading is not supported in this build.
                // Return false so the Dart layer falls back to ML Kit descriptions.
                result.success(false)
            }
            "analyzeImage" -> {
                val imageBytes = call.argument<ByteArray>("imageBytes")
                    ?: return result.error("INVALID_ARGUMENT", "imageBytes required", null)
                val prompt = call.argument<String>("prompt") ?: "Describe this image"
                handleAnalyzeImage(imageBytes, prompt, result)
            }
            "generateText" -> {
                // LLM text generation is not supported in this build.
                result.error("MODEL_NOT_LOADED", "On-device LLM not available. Analysis uses ML Kit.", null)
            }
            "isModelLoaded" -> result.success(false)
            "unloadModel"   -> result.success(true)
            else            -> result.notImplemented()
        }
    }

    // ── analyzeImage ──────────────────────────────────────────────────────
    //
    // Pipeline:
    //   1. Decode JPEG bytes from camera
    //   2. ML Kit: image labels  (scene classification)
    //   3. ML Kit: object detection  (position-aware object list)
    //   4. ML Kit: text recognition  (OCR)
    //   5. Format results into an accessible description

    private fun handleAnalyzeImage(imageBytes: ByteArray, prompt: String, result: Result) {
        scope.launch {
            try {
                val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                    ?: throw Exception("Could not decode image")

                val (labels, objects, texts) = analyzeWithMlKit(bitmap)
                bitmap.recycle()

                val response = buildDescription(labels, objects, texts, prompt)
                mainResult(result) { it.success(response) }

            } catch (e: Exception) {
                Log.e(TAG, "analyzeImage failed: ${e.message}")
                mainResult(result) {
                    it.error("INFERENCE_ERROR", e.message ?: "Analysis failed", null)
                }
            }
        }
    }

    // ── ML Kit helpers ─────────────────────────────────────────────────────

    private data class MlKitResults(
        val labels: List<String>,
        val objects: List<String>,
        val texts: List<String>
    )

    private suspend fun analyzeWithMlKit(bitmap: Bitmap): MlKitResults {
        val image = InputImage.fromBitmap(bitmap, 0)
        val labelsDeferred  = scope.async { runLabeler(image) }
        val objectsDeferred = scope.async { runObjectDetector(image) }
        val textsDeferred   = scope.async { runTextRecognizer(image) }
        return MlKitResults(
            labels  = labelsDeferred.await(),
            objects = objectsDeferred.await(),
            texts   = textsDeferred.await()
        )
    }

    private suspend fun runLabeler(image: InputImage): List<String> =
        suspendCoroutine { cont ->
            labeler.process(image)
                .addOnSuccessListener { labels ->
                    cont.resume(labels.map { "${it.text} (${(it.confidence * 100).toInt()}%)" })
                }
                .addOnFailureListener { cont.resumeWithException(it) }
        }

    private suspend fun runObjectDetector(image: InputImage): List<String> =
        suspendCoroutine { cont ->
            objectDetector.process(image)
                .addOnSuccessListener { objects ->
                    cont.resume(objects.map { obj ->
                        val label = obj.labels.firstOrNull()?.text ?: "unknown object"
                        val box = obj.boundingBox
                        val pos = when {
                            box.centerX() < image.width  * 0.33 -> "left"
                            box.centerX() < image.width  * 0.66 -> "centre"
                            else                                  -> "right"
                        }
                        val dist = if (box.height() > image.height * 0.4) "near" else "far"
                        "$label at $pos, $dist"
                    })
                }
                .addOnFailureListener { cont.resumeWithException(it) }
        }

    private suspend fun runTextRecognizer(image: InputImage): List<String> =
        suspendCoroutine { cont ->
            textRecognizer.process(image)
                .addOnSuccessListener { visionText ->
                    val lines = visionText.textBlocks
                        .flatMap { it.lines }
                        .map { it.text.trim() }
                        .filter { it.isNotBlank() }
                    cont.resume(lines)
                }
                .addOnFailureListener { cont.resumeWithException(it) }
        }

    // ── Description builder ────────────────────────────────────────────────

    private fun buildDescription(
        labels: List<String>,
        objects: List<String>,
        texts: List<String>,
        prompt: String
    ): String = buildString {
        val mode = prompt.lowercase()
        when {
            mode.contains("text") || mode.contains("read") -> {
                if (texts.isEmpty()) append("No text detected in the image.")
                else { append("Text found: "); append(texts.joinToString(". ")) }
            }
            mode.contains("navig") || mode.contains("walk") -> {
                append("Scene: ")
                if (labels.isNotEmpty()) append(labels.take(3).map { it.substringBefore(" (") }.joinToString(", "))
                if (objects.isNotEmpty()) { append(". Objects: "); append(objects.take(4).joinToString("; ")) }
                append(". Proceed carefully.")
            }
            else -> {
                if (labels.isNotEmpty()) {
                    append("Scene contains: ")
                    append(labels.take(5).map { it.substringBefore(" (") }.joinToString(", "))
                    append(". ")
                }
                if (objects.isNotEmpty()) {
                    append("Objects detected: ")
                    append(objects.take(4).joinToString("; "))
                    append(". ")
                }
                if (texts.isNotEmpty()) {
                    append("Visible text: ")
                    append(texts.take(3).joinToString(". "))
                }
                if (isEmpty()) append("Scene unclear. Move closer or improve lighting.")
            }
        }
    }

    // ── Utility ────────────────────────────────────────────────────────────

    private suspend fun mainResult(result: Result, block: (Result) -> Unit) =
        withContext(Dispatchers.Main) { block(result) }
}
