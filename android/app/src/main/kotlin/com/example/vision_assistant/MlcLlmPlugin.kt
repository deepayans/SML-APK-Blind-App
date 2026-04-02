package com.example.vision_assistant

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.google.mlkit.vision.common.InputImage
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
 * On-device vision plugin using two ML Kit APIs:
 *   • Object Detection  — detects objects with spatial positions
 *   • Text Recognition  — OCR on any visible text
 *
 * Image labeling (scene classification) was removed because its dependency
 * (com.google.mlkit:image-labeling) fails to resolve ImageLabelerOptions at
 * compile time regardless of version. Object detection provides equivalent
 * scene understanding for navigation and accessibility purposes.
 */
class MlcLlmPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

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
            "loadModel"     -> result.success(false)
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

                val objectsJob = async { detectObjects(image, bitmapWidth, bitmapHeight) }
                val textsJob   = async { recognizeText(image) }

                val objects = objectsJob.await()
                val texts   = textsJob.await()

                bitmap.recycle()

                val response = buildDescription(objects, texts, prompt)
                withContext(Dispatchers.Main) { result.success(response) }

            } catch (e: Exception) {
                Log.e(TAG, "analyzeImage error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("INFERENCE_ERROR", e.message ?: "Analysis failed", null)
                }
            }
        }
    }

    private suspend fun detectObjects(
        image: InputImage,
        bitmapWidth: Int,
        bitmapHeight: Int
    ): List<String> = suspendCoroutine { cont ->
        objectDetector.process(image)
            .addOnSuccessListener { detectedObjects ->
                val descriptions = detectedObjects.map { obj ->
                    val label = obj.labels.firstOrNull()?.text ?: "object"
                    val cx    = obj.boundingBox.exactCenterX()
                    val pos   = when {
                        cx < bitmapWidth * 0.33f -> "left"
                        cx < bitmapWidth * 0.66f -> "centre"
                        else                      -> "right"
                    }
                    val near  = obj.boundingBox.height() > bitmapHeight * 0.4f
                    "$label at $pos${if (near) ", close" else ""}"
                }
                cont.resume(descriptions)
            }
            .addOnFailureListener { cont.resumeWithException(it) }
    }

    private suspend fun recognizeText(image: InputImage): List<String> =
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
        objects: List<String>,
        texts: List<String>,
        prompt: String
    ): String = buildString {
        val mode = prompt.lowercase()
        when {
            mode.contains("text") || mode.contains("read") -> {
                if (texts.isEmpty()) append("No text detected.")
                else { append("Text: "); append(texts.joinToString(". ")) }
            }
            mode.contains("navig") || mode.contains("walk") -> {
                if (objects.isEmpty()) {
                    append("Path appears clear. Proceed carefully.")
                } else {
                    append("Objects ahead: ")
                    append(objects.take(5).joinToString("; "))
                    append(". Proceed with caution.")
                }
            }
            else -> {
                if (objects.isNotEmpty()) {
                    append("Detected: ")
                    append(objects.take(5).joinToString("; "))
                    append(". ")
                }
                if (texts.isNotEmpty()) {
                    append("Text visible: ")
                    append(texts.take(3).joinToString(". "))
                }
                if (isEmpty()) append("Nothing clearly detected. Move closer or improve lighting.")
            }
        }
    }
}
