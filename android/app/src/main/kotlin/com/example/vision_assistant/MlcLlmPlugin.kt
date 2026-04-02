package com.example.vision_assistant

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.google.mediapipe.tasks.genai.llminference.LlmInference
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
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

private const val TAG = "VisionPlugin"

/**
 * Two-stage on-device vision pipeline:
 *
 * Stage 1 — ML Kit SML (instant, always available):
 *   • Object Detection  → what objects exist and where (left/centre/right, near/far)
 *   • Text Recognition  → any readable text in the frame
 *
 * Stage 2 — Gemma 2B SLM via MediaPipe (after one-time download):
 *   • Takes ML Kit's structured detections as a prompt
 *   • Generates fluent, context-aware natural language descriptions
 *   • Runs fully offline after the ~1.5 GB model is downloaded
 *
 * If Gemma has not been downloaded yet, Stage 1 output is returned directly
 * as a structured fallback so the app is never completely silent.
 */
class MlcLlmPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    // Single-threaded to serialise LLM calls (LlmInference is not thread-safe)
    private val llmThread = Dispatchers.IO.limitedParallelism(1)
    private val scope     = CoroutineScope(llmThread + SupervisorJob())

    private var llm: LlmInference? = null

    // ── ML Kit detectors (lazy, stateless, thread-safe) ───────────────────

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

    // ── Plugin lifecycle ──────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "mlc_llm_channel")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.launch { llm?.close(); llm = null }
        scope.cancel()
    }

    // ── Method dispatch ───────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "loadModel" -> {
                val modelPath = call.argument<String>("modelPath")
                    ?: return result.error("INVALID_ARGUMENT", "modelPath required", null)
                loadModel(modelPath, result)
            }
            "analyzeImage" -> {
                val imageBytes = call.argument<ByteArray>("imageBytes")
                    ?: return result.error("INVALID_ARGUMENT", "imageBytes required", null)
                val prompt = call.argument<String>("prompt") ?: "Describe this image"
                analyzeImage(imageBytes, prompt, result)
            }
            "isModelLoaded" -> result.success(llm != null)
            "unloadModel"   -> unloadModel(result)
            "generateText"  -> {
                val prompt = call.argument<String>("prompt")
                    ?: return result.error("INVALID_ARGUMENT", "prompt required", null)
                generateText(prompt, result)
            }
            else -> result.notImplemented()
        }
    }

    // ── loadModel — initialise Gemma 2B via MediaPipe LlmInference ────────

    private fun loadModel(modelPath: String, result: Result) {
        scope.launch {
            try {
                // Accept a directory path (find .bin inside) or a direct file path
                val modelFile = resolveModelFile(modelPath)
                    ?: return@launch main(result) {
                        it.error("MODEL_NOT_FOUND",
                            "No .bin model file found in $modelPath", null)
                    }

                Log.i(TAG, "Loading Gemma from: ${modelFile.absolutePath}")
                llm?.close()

                val options = LlmInference.LlmInferenceOptions.builder()
                    .setModelPath(modelFile.absolutePath)
                    .setMaxTokens(512)
                    .setTopK(40)
                    .setTemperature(0.8f)
                    .build()

                llm = LlmInference.createFromOptions(context, options)
                Log.i(TAG, "Gemma loaded successfully")
                main(result) { it.success(true) }

            } catch (e: Exception) {
                Log.e(TAG, "loadModel failed: ${e.message}")
                main(result) { it.error("LOAD_ERROR", e.message, null) }
            }
        }
    }

    private fun resolveModelFile(path: String): File? {
        val f = File(path)
        return when {
            f.isFile -> f
            f.isDirectory -> f.listFiles()
                ?.firstOrNull { it.extension == "bin" || it.extension == "task" }
            else -> null
        }
    }

    // ── analyzeImage — ML Kit → Gemma pipeline ────────────────────────────

    private fun analyzeImage(imageBytes: ByteArray, prompt: String, result: Result) {
        scope.launch {
            try {
                val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                    ?: throw Exception("Could not decode image")

                val w = bitmap.width
                val h = bitmap.height
                val image = InputImage.fromBitmap(bitmap, 0)

                // Stage 1: ML Kit (parallel)
                val objJob  = async(Dispatchers.IO) { detectObjects(image, w, h) }
                val txtJob  = async(Dispatchers.IO) { recognizeText(image) }
                val objects = objJob.await()
                val texts   = txtJob.await()
                bitmap.recycle()

                // Stage 2: Gemma generates fluent description from detections
                val response = if (llm != null) {
                    val gemmaPrompt = buildGemmaPrompt(objects, texts, prompt)
                    llm!!.generateResponse(gemmaPrompt)
                } else {
                    // Gemma not yet downloaded — return ML Kit result directly
                    buildFallback(objects, texts, prompt)
                }

                main(result) { it.success(response.trim()) }

            } catch (e: Exception) {
                Log.e(TAG, "analyzeImage error: ${e.message}")
                main(result) { it.error("INFERENCE_ERROR", e.message, null) }
            }
        }
    }

    // ── Gemma prompt builder ──────────────────────────────────────────────

    private fun buildGemmaPrompt(
        objects: List<String>,
        texts: List<String>,
        userRequest: String
    ): String {
        val detections = buildString {
            if (objects.isNotEmpty()) appendLine("Objects: ${objects.joinToString("; ")}")
            if (texts.isNotEmpty())   appendLine("Visible text: ${texts.joinToString(" | ")}")
            if (objects.isEmpty() && texts.isEmpty()) appendLine("No clear objects or text detected.")
        }

        return """You are a vision assistant for a visually impaired person. \
Be concise, specific and mention spatial positions (left, right, centre, near, far). \
Highlight hazards first.

Scene detections:
$detections
Task: $userRequest

Response:""".trimIndent()
    }

    // ── ML Kit helpers ────────────────────────────────────────────────────

    private suspend fun detectObjects(
        image: InputImage,
        bitmapWidth: Int,
        bitmapHeight: Int
    ): List<String> = suspendCoroutine { cont ->
        objectDetector.process(image)
            .addOnSuccessListener { detected ->
                cont.resume(detected.map { obj ->
                    val label = obj.labels.firstOrNull()?.text ?: "object"
                    val cx    = obj.boundingBox.exactCenterX()
                    val pos   = when {
                        cx < bitmapWidth * 0.33f -> "left"
                        cx < bitmapWidth * 0.66f -> "centre"
                        else                      -> "right"
                    }
                    val near  = obj.boundingBox.height() > bitmapHeight * 0.4f
                    "$label at $pos${if (near) ", close" else ""}"
                })
            }
            .addOnFailureListener { cont.resumeWithException(it) }
    }

    private suspend fun recognizeText(image: InputImage): List<String> =
        suspendCoroutine { cont ->
            textRecognizer.process(image)
                .addOnSuccessListener { vt ->
                    cont.resume(
                        vt.textBlocks.flatMap { it.lines }
                            .map { it.text.trim() }
                            .filter { it.isNotBlank() }
                    )
                }
                .addOnFailureListener { cont.resumeWithException(it) }
        }

    // ── Fallback when Gemma not downloaded ────────────────────────────────

    private fun buildFallback(
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
                if (objects.isEmpty()) append("Path appears clear. Proceed carefully.")
                else { append("Objects ahead: "); append(objects.take(5).joinToString("; ")) }
            }
            else -> {
                if (objects.isNotEmpty()) {
                    append("Detected: "); append(objects.take(5).joinToString("; ")); append(". ")
                }
                if (texts.isNotEmpty()) {
                    append("Text: "); append(texts.take(3).joinToString(". "))
                }
                if (isEmpty()) append("Nothing clearly detected. Move closer.")
            }
        }
    }

    // ── generateText ──────────────────────────────────────────────────────

    private fun generateText(prompt: String, result: Result) {
        scope.launch {
            val model = llm ?: return@launch main(result) {
                it.error("MODEL_NOT_LOADED", "Gemma not loaded", null)
            }
            try {
                main(result) { it.success(model.generateResponse(prompt)) }
            } catch (e: Exception) {
                main(result) { it.error("INFERENCE_ERROR", e.message, null) }
            }
        }
    }

    // ── unloadModel ───────────────────────────────────────────────────────

    private fun unloadModel(result: Result) {
        scope.launch {
            try { llm?.close(); llm = null; main(result) { it.success(true) } }
            catch (e: Exception) { main(result) { it.error("UNLOAD_ERROR", e.message, null) } }
        }
    }

    private suspend fun main(result: Result, block: (Result) -> Unit) =
        withContext(Dispatchers.Main) { block(result) }
}
