package com.example.vision_assistant

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInference.LlmInferenceOptions
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
 * Two-stage fully offline vision pipeline.
 *
 * Stage 1 — ML Kit (instant, no download):
 *   • Object Detection  — finds objects and their positions
 *   • Text Recognition  — reads any visible text (OCR)
 *
 * Stage 2 — Gemma 2B SLM via Google AI Edge / LiteRT (first-launch download):
 *   • Receives ML Kit detections as a structured prompt
 *   • Generates fluent natural-language descriptions
 *   • Fully offline after the one-time ~1.5 GB download
 *   • Uses LiteRT (Google's on-device inference engine) — no cloud, no API key
 *
 * If the model hasn't been downloaded yet, Stage 1 output is returned as-is.
 */
class MlcLlmPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    // Gemma is NOT thread-safe — all LLM calls on one dedicated thread
    private val llmDispatcher = Dispatchers.IO.limitedParallelism(1)
    // ML Kit is thread-safe — runs on general IO pool
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private var gemma: LlmInference? = null

    // ── ML Kit (lazy, reused across calls) ───────────────────────────────

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
        scope.launch(llmDispatcher) { gemma?.close(); gemma = null }
        scope.cancel()
    }

    // ── Method dispatch ───────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "loadModel" -> {
                val path = call.argument<String>("modelPath")
                    ?: return result.error("INVALID_ARGUMENT", "modelPath required", null)
                loadGemma(path, result)
            }
            "analyzeImage" -> {
                val bytes = call.argument<ByteArray>("imageBytes")
                    ?: return result.error("INVALID_ARGUMENT", "imageBytes required", null)
                val prompt = call.argument<String>("prompt") ?: "Describe this image"
                analyzeImage(bytes, prompt, result)
            }
            "isModelLoaded" -> result.success(gemma != null)
            "unloadModel"   -> unload(result)
            "generateText"  -> {
                val prompt = call.argument<String>("prompt")
                    ?: return result.error("INVALID_ARGUMENT", "prompt required", null)
                generateText(prompt, result)
            }
            else -> result.notImplemented()
        }
    }

    // ── Load Gemma 2B ─────────────────────────────────────────────────────

    private fun loadGemma(modelPath: String, result: Result) {
        scope.launch(llmDispatcher) {
            try {
                val file = findModelFile(modelPath)
                    ?: return@launch reply(result) {
                        it.error("MODEL_NOT_FOUND", "No .bin file found in $modelPath", null)
                    }

                Log.i(TAG, "Loading Gemma 2B from: ${file.absolutePath}")
                gemma?.close()

                // LlmInferenceOptions in tasks-genai 0.10.8:
                // Only setModelPath and setMaxTokens are safe to call.
                val options = LlmInferenceOptions.builder()
                    .setModelPath(file.absolutePath)
                    .setMaxTokens(512)
                    .build()

                gemma = LlmInference.createFromOptions(context, options)
                Log.i(TAG, "Gemma 2B loaded successfully")
                reply(result) { it.success(true) }

            } catch (e: Exception) {
                Log.e(TAG, "loadGemma failed: ${e.message}")
                reply(result) { it.error("LOAD_ERROR", e.message ?: "Load failed", null) }
            }
        }
    }

    private fun findModelFile(path: String): File? {
        val f = File(path)
        return when {
            f.isFile      -> f
            f.isDirectory -> f.listFiles()
                ?.firstOrNull { it.extension == "bin" || it.extension == "task" }
            else          -> null
        }
    }

    // ── analyzeImage: ML Kit → Gemma pipeline ────────────────────────────

    private fun analyzeImage(imageBytes: ByteArray, prompt: String, result: Result) {
        scope.launch {
            try {
                val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                    ?: throw Exception("Could not decode image")

                val w = bitmap.width
                val h = bitmap.height
                val image = InputImage.fromBitmap(bitmap, 0)

                // Stage 1: run both ML Kit tasks in parallel (thread-safe)
                val objJob = async { detectObjects(image, w, h) }
                val txtJob = async { recognizeText(image) }
                val objects = objJob.await()
                val texts   = txtJob.await()
                bitmap.recycle()

                // Stage 2: switch to single-threaded LLM dispatcher for Gemma
                val response = withContext(llmDispatcher) {
                    val model = gemma
                    if (model != null) {
                        model.generateResponse(buildPrompt(objects, texts, prompt))
                    } else {
                        buildFallback(objects, texts, prompt)
                    }
                }

                reply(result) { it.success(response.trim()) }

            } catch (e: Exception) {
                Log.e(TAG, "analyzeImage error: ${e.message}")
                reply(result) {
                    it.error("INFERENCE_ERROR", e.message ?: "Analysis failed", null)
                }
            }
        }
    }

    // ── Gemma prompt ──────────────────────────────────────────────────────

    private fun buildPrompt(objects: List<String>, texts: List<String>, task: String): String {
        val scene = buildString {
            if (objects.isNotEmpty()) appendLine("Objects: ${objects.joinToString("; ")}")
            if (texts.isNotEmpty())   appendLine("Text visible: ${texts.joinToString(" | ")}")
            if (objects.isEmpty() && texts.isEmpty()) appendLine("Nothing detected.")
        }.trim()

        return """You are a vision assistant for a visually impaired person.
Be concise (2-3 sentences). State positions (left/right/centre, near/far). Mention hazards first.

Scene: $scene
Task: $task
Response:"""
    }

    // ── ML Kit helpers ────────────────────────────────────────────────────

    private suspend fun detectObjects(image: InputImage, w: Int, h: Int): List<String> =
        suspendCoroutine { cont ->
            objectDetector.process(image)
                .addOnSuccessListener { items ->
                    cont.resume(items.map { obj ->
                        val label = obj.labels.firstOrNull()?.text ?: "object"
                        val cx  = obj.boundingBox.exactCenterX()
                        val pos = when {
                            cx < w * 0.33f -> "left"
                            cx < w * 0.66f -> "centre"
                            else           -> "right"
                        }
                        val near = obj.boundingBox.height() > h * 0.4f
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

    // ── Fallback: Gemma not yet downloaded ───────────────────────────────

    private fun buildFallback(objects: List<String>, texts: List<String>, prompt: String): String =
        buildString {
            val mode = prompt.lowercase()
            when {
                mode.contains("text") || mode.contains("read") -> {
                    if (texts.isEmpty()) append("No text detected.")
                    else { append("Text: "); append(texts.joinToString(". ")) }
                }
                mode.contains("navig") || mode.contains("walk") -> {
                    if (objects.isEmpty()) append("Path clear. Proceed carefully.")
                    else { append("Objects: "); append(objects.take(5).joinToString("; ")) }
                }
                else -> {
                    if (objects.isNotEmpty()) {
                        append("Detected: ")
                        append(objects.take(5).joinToString("; "))
                        append(". ")
                    }
                    if (texts.isNotEmpty()) {
                        append("Text: ")
                        append(texts.take(3).joinToString(". "))
                    }
                    if (isEmpty()) append("Nothing clearly detected. Move closer.")
                }
            }
        }

    // ── generateText / unload ─────────────────────────────────────────────

    private fun generateText(prompt: String, result: Result) {
        scope.launch(llmDispatcher) {
            val model = gemma ?: return@launch reply(result) {
                it.error("MODEL_NOT_LOADED", "Gemma not loaded yet", null)
            }
            try {
                reply(result) { it.success(model.generateResponse(prompt)) }
            } catch (e: Exception) {
                reply(result) { it.error("INFERENCE_ERROR", e.message ?: "Failed", null) }
            }
        }
    }

    private fun unload(result: Result) {
        scope.launch(llmDispatcher) {
            try {
                gemma?.close(); gemma = null
                reply(result) { it.success(true) }
            } catch (e: Exception) {
                reply(result) { it.error("UNLOAD_ERROR", e.message, null) }
            }
        }
    }

    private suspend fun reply(result: Result, block: (Result) -> Unit) =
        withContext(Dispatchers.Main) { block(result) }
}
