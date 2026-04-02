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

class MlcLlmPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

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

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "mlc_llm_channel")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "loadModel"     -> result.success(false)   // no LLM in this build
            "isModelLoaded" -> result.success(false)
            "unloadModel"   -> result.success(true)
            "generateText"  -> result.error("NOT_SUPPORTED", "LLM not available", null)
            "analyzeImage"  -> {
                val imageBytes = call.argument<ByteArray>("imageBytes")
                    ?: return result.error("INVALID_ARGUMENT", "imageBytes required", null)
                val prompt = call.argument<String>("prompt") ?: "Describe this image"
                analyzeImage(imageBytes, prompt, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun analyzeImage(imageBytes: ByteArray, prompt: String, result: Result) {
        scope.launch {
            try {
                val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                    ?: throw Exception("Could not decode image")

                val bitmapWidth  = bitmap.width
                val bitmapHeight = bitmap.height
                val image        = InputImage.fromBitmap(bitmap, 0)

                // Run all three ML Kit tasks in parallel
                val labelsJob  = async { runLabeler(image) }
                val objectsJob = async { runObjectDetector(image, bitmapWidth, bitmapHeight) }
                val textsJob   = async { runTextRecognizer(image) }

                val labels  = labelsJob.await()
                val objects = objectsJob.await()
                val texts   = textsJob.await()

                bitmap.recycle()

                val response = buildDescription(labels, objects, texts, prompt)
                withContext(Dispatchers.Main) { result.success(response) }

            } catch (e: Exception) {
                Log.e(TAG, "analyzeImage error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("INFERENCE_ERROR", e.message ?: "Analysis failed", null)
                }
            }
        }
    }

    private suspend fun runLabeler(image: InputImage): List<String> =
        suspendCoroutine { cont ->
            labeler.process(image)
                .addOnSuccessListener { labels ->
                    cont.resume(labels.map { "${it.text} (${(it.confidence * 100).toInt()}%)" })
                }
                .addOnFailureListener { cont.resumeWithException(it) }
        }

    // bitmapWidth/bitmapHeight are passed in to avoid using InputImage.width/height,
    // which requires vision-common >= 17.3 and may not resolve via transitive deps.
    private suspend fun runObjectDetector(
        image: InputImage,
        bitmapWidth: Int,
        bitmapHeight: Int
    ): List<String> =
        suspendCoroutine { cont ->
            objectDetector.process(image)
                .addOnSuccessListener { detectedObjects ->
                    cont.resume(detectedObjects.map { obj ->
                        val label = obj.labels.firstOrNull()?.text ?: "object"
                        val cx    = obj.boundingBox.exactCenterX()
                        val pos   = when {
                            cx < bitmapWidth * 0.33f -> "left"
                            cx < bitmapWidth * 0.66f -> "centre"
                            else                      -> "right"
                        }
                        val near = obj.boundingBox.height() > bitmapHeight * 0.4f
                        "$label at $pos, ${if (near) "near" else "far"}"
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

    private fun buildDescription(
        labels: List<String>,
        objects: List<String>,
        texts: List<String>,
        prompt: String
    ): String = buildString {
        val mode = prompt.lowercase()
        when {
            mode.contains("text") || mode.contains("read") -> {
                if (texts.isEmpty()) append("No text detected.")
                else { append("Text found: "); append(texts.joinToString(". ")) }
            }
            mode.contains("navig") || mode.contains("walk") -> {
                append("Scene: ")
                if (labels.isNotEmpty())
                    append(labels.take(3).joinToString(", ") { it.substringBefore(" (") })
                if (objects.isNotEmpty()) {
                    append(". Objects: ")
                    append(objects.take(4).joinToString("; "))
                }
                append(". Proceed carefully.")
            }
            else -> {
                if (labels.isNotEmpty()) {
                    append("Scene contains: ")
                    append(labels.take(5).joinToString(", ") { it.substringBefore(" (") })
                    append(". ")
                }
                if (objects.isNotEmpty()) {
                    append("Objects: ")
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
}
