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
 *   Stage 1 — ML Kit (instant, no download):
 *     Object Detection + Text Recognition → structured scene data
 *
 *   Stage 2 — Gemma 2B via MediaPipe LlmInference (after first-launch download):
 *     Structured detections → fluent natural-language description
 *     Runs fully offline after the ~1.5 GB model is in place.
 */
class MlcLlmPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    // LlmInference is NOT thread-safe — keep all LLM calls on one thread.
    // ML Kit tasks run on their own IO threads via the Task API so they
    // don't need to share this dispatcher.
    private val llmDispatcher = Dispatchers.IO.limitedParallelism(1)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private var llm: LlmInference? = null

    // ── ML Kit clients ────────────────────────────────────────────────────

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
        scope.launch(llmDispatcher) { llm?.close(); llm = null }
        scope.cancel()
    }

    // ── Method dispatch ───────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "loadModel" -> {
                val path = call.argument<String>("modelPath")
                    ?: return result.error("INVALID_ARGUMENT", "modelPath required", null)
                handleLoadModel(path, result)
            }
            "analyzeImage" -> {
                val bytes = call.argument<ByteArray>("imageBytes")
                    ?: return result.error("INVALID_ARGUMENT", "imageBytes required", null)
                val prompt = call.argument<String>("prompt") ?: "Describe this image"
                handleAnalyzeImage(bytes, prompt, result)
            }
            "isModelLoaded" -> result.success(llm != null)
            "unloadModel"   -> handleUnload(result)
            "generateText"  -> {
                val prompt = call.argument<String>("prompt")
                    ?: return result.error("INVALID_ARGUMENT", "prompt required", null)
                handleGenerateText(prompt, result)
            }
            else -> result.notImplemented()
        }
    }

    // ── loadModel ─────────────────────────────────────────────────────────

    private fun handleLoadModel(modelPath: String, result: Result) {
        scope.launch(llmDispatcher) {
            try {
                val modelFile = resolveModelFile(modelPath)
                    ?: return@launch reply(result) {
                        it.error("MODEL_NOT_FOUND", "No .bin file in $modelPath", null)
                    }

                Log.i(TAG, "Loading Gemma: ${modelFile.absolutePath}")
                llm?.close()

                // Only setModelPath and setMaxTokens are available in tasks-genai 0.10.14.
                // setTopK / setTemperature were added in later versions — omitting them
                // prevents NoSuchMethodError crashes.
                val options = LlmInference.LlmInferenceOptions.builder()
                    .setModelPath(modelFile.absolutePath)
                    .setMaxTokens(512)
                    .build()

                llm = LlmInference.createFromOptions(context, options)
                Log.i(TAG, "Gemma loaded OK")
                reply(result) { it.success(true) }

            } catch (e: Exception) {
                Log.e(TAG, "loadModel: ${e.message}")
                reply(result) { it.error("LOAD_ERROR", e.message ?: "Load failed", null) }
            }
        }
    }

    private fun resolveModelFile(path: String): File? {
        val f = File(path)
        return when {
            f.isFile      -> f
            f.isDirectory -> f.listFiles()
                ?.firstOrNull { it.extension == "bin" || it.extension == "task" }
            else          -> null
        }
    }

    // ── analyzeImage — ML Kit → Gemma pipeline ────────────────────────────

    private fun handleAnalyzeImage(imageBytes: ByteArray, prompt: String, result: Result) {
        // Stage 1 runs on general IO threads (ML Kit is thread-safe)
        scope.launch {
            try {
                val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                    ?: throw Exception("Could not decode image")

                val w = bitmap.width
                val h = bitmap.height
                val image = InputImage.fromBitmap(bitmap, 0)

                // Run both ML Kit tasks in parallel on IO
                val objDeferred = async { detectObjects(image, w, h) }
                val txtDeferred = async { recognizeText(image) }
                val objects = objDeferred.await()
                val texts   = txtDeferred.await()
                bitmap.recycle()

                // Stage 2: run Gemma on its dedicated single-threaded dispatcher
                val response = withContext(llmDispatcher) {
                    val model = llm
                    if (model != null) {
                        val gemmaPrompt = buildGemmaPrompt(objects, texts, prompt)
                        model.generateResponse(gemmaPrompt)
                    } else {
                        buildFallback(objects, texts, prompt)
                    }
                }

                reply(result) { it.success(response.trim()) }

            } catch (e: Exception) {
                Log.e(TAG, "analyzeImage: ${e.message}")
                reply(result) { it.error("INFERENCE_ERROR", e.message ?: "Analysis failed", null) }
            }
        }
    }

    // ── Gemma prompt ──────────────────────────────────────────────────────

    private fun buildGemmaPrompt(objects: List<String>, texts: List<String>, task: String): String {
        val detections = buildString {
            if (objects.isNotEmpty()) appendLine("Objects: ${objects.joinToString("; ")}")
            if (texts.isNotEmpty())   appendLine("Visible text: ${texts.joinToString(" | ")}")
            if (objects.isEmpty() && texts.isEmpty()) appendLine("No objects or text detected.")
        }.trim()

        return """You are a vision assistant for a visually impaired person.
Be concise (2-3 sentences). State positions (left/right/centre, near/far). Mention hazards first.

Scene: $detections
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
                        val cx = obj.boundingBox.exactCenterX()
                        val pos = when {
                            cx < w * 0.33f -> "left"
                            cx < w * 0.66f -> "centre"
                            else -> "right"
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

    // ── Fallback (Gemma not yet downloaded) ───────────────────────────────

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
                    if (objects.isNotEmpty()) { append("Detected: "); append(objects.take(5).joinToString("; ")); append(". ") }
                    if (texts.isNotEmpty()) { append("Text: "); append(texts.take(3).joinToString(". ")) }
                    if (isEmpty()) append("Nothing clearly detected. Move closer.")
                }
            }
        }

    // ── generateText / unload ─────────────────────────────────────────────

    private fun handleGenerateText(prompt: String, result: Result) {
        scope.launch(llmDispatcher) {
            val model = llm ?: return@launch reply(result) {
                it.error("MODEL_NOT_LOADED", "Gemma not loaded", null)
            }
            try {
                reply(result) { it.success(model.generateResponse(prompt)) }
            } catch (e: Exception) {
                reply(result) { it.error("INFERENCE_ERROR", e.message ?: "Failed", null) }
            }
        }
    }

    private fun handleUnload(result: Result) {
        scope.launch(llmDispatcher) {
            try { llm?.close(); llm = null; reply(result) { it.success(true) } }
            catch (e: Exception) { reply(result) { it.error("UNLOAD_ERROR", e.message, null) } }
        }
    }

    private suspend fun reply(result: Result, block: (Result) -> Unit) =
        withContext(Dispatchers.Main) { block(result) }
}
