package com.example.vision_assistant

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.google.mediapipe.tasks.genai.llminference.LlmInference
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
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

private const val TAG = "VisionPlugin"

/**
 * Flutter platform channel plugin that powers on-device vision inference.
 *
 * Architecture:
 *   ML Kit  →  detects labels / objects / text in the image (always offline,
 *              no model download required beyond first Play Services sync)
 *   Gemma 2B via MediaPipe  →  turns detections into a natural-language
 *              description (optional; requires one-time ~1.5 GB download)
 *
 * If Gemma is not yet downloaded the plugin returns a structured description
 * built from ML Kit results alone — still useful for a blind user.
 */
class MlcLlmPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    // MediaPipe Gemma (optional — app works without it via ML Kit only)
    private var llm: LlmInference? = null

    // Single-threaded dispatcher keeps MLKit + LLM calls serialised
    private val workerThread = Dispatchers.IO.limitedParallelism(1)
    private val scope = CoroutineScope(workerThread + SupervisorJob())

    // ── ML Kit clients (created lazily, reused across calls) ─────────────

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
        scope.launch { llm?.close(); llm = null }
        scope.cancel()
    }

    // ── Method dispatch ───────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "loadModel" -> {
                val modelPath = call.argument<String>("modelPath")
                    ?: return result.error("INVALID_ARGUMENT", "modelPath required", null)
                handleLoadModel(modelPath, result)
            }
            "analyzeImage" -> {
                val imageBytes = call.argument<ByteArray>("imageBytes")
                    ?: return result.error("INVALID_ARGUMENT", "imageBytes required", null)
                val prompt = call.argument<String>("prompt") ?: "Describe this image"
                handleAnalyzeImage(imageBytes, prompt, result)
            }
            "generateText" -> {
                val prompt = call.argument<String>("prompt")
                    ?: return result.error("INVALID_ARGUMENT", "prompt required", null)
                handleGenerateText(prompt, result)
            }
            "isModelLoaded" -> result.success(llm != null)
            "unloadModel"   -> handleUnloadModel(result)
            else            -> result.notImplemented()
        }
    }

    // ── loadModel ─────────────────────────────────────────────────────────
    //
    // Loads the Gemma 2B task file via MediaPipe LlmInference.
    // The model file is the single *.bin / *.task that ModelDownloader saves.

    private fun handleLoadModel(modelPath: String, result: Result) {
        scope.launch {
            try {
                val dir = File(modelPath)
                // Accept either a directory (find the .bin/.task inside) or a direct file path
                val modelFile: File = if (dir.isDirectory) {
                    dir.listFiles()
                        ?.firstOrNull { it.extension == "bin" || it.extension == "task" }
                        ?: throw Exception(
                            "No .bin or .task model file found in $modelPath. " +
                            "Complete the model download first."
                        )
                } else {
                    dir.takeIf { it.exists() }
                        ?: throw Exception("Model file not found: $modelPath")
                }

                Log.i(TAG, "Loading Gemma from: ${modelFile.absolutePath}")

                llm?.close()

                val options = LlmInference.LlmInferenceOptions.builder()
                    .setModelPath(modelFile.absolutePath)
                    .setMaxTokens(512)
                    .build()

                llm = LlmInference.createFromOptions(context, options)
                Log.i(TAG, "Gemma loaded successfully")
                mainResult(result) { it.success(true) }

            } catch (e: Exception) {
                Log.e(TAG, "loadModel failed: ${e.message}")
                mainResult(result) {
                    it.error("LOAD_ERROR", e.message ?: "Failed to load model", null)
                }
            }
        }
    }

    // ── analyzeImage ──────────────────────────────────────────────────────
    //
    // Pipeline:
    //   1. Decode JPEG from camera
    //   2. ML Kit: image labels  (what things are in the scene)
    //   3. ML Kit: object detection  (where they are)
    //   4. ML Kit: text recognition  (any visible text)
    //   5a. If Gemma loaded → format detections as a prompt, generate response
    //   5b. Otherwise → format detections as a structured description

    private fun handleAnalyzeImage(imageBytes: ByteArray, prompt: String, result: Result) {
        scope.launch {
            try {
                val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                    ?: throw Exception("Could not decode image")

                // Run all three ML Kit tasks in parallel
                val (labels, objects, texts) = analyzeWithMlKit(bitmap)
                bitmap.recycle()

                val response: String = if (llm != null) {
                    // Build a rich prompt from detections, let Gemma describe naturally
                    val detectionContext = buildDetectionContext(labels, objects, texts)
                    val gemmaPrompt = """
You are a vision assistant for a visually impaired person.
The following elements were detected in the image:
$detectionContext

Based on these detections, respond to this request: $prompt

Be concise, specific, and include spatial positions where known.
Mention any hazards prominently.
""".trimIndent()
                    llm!!.generateResponse(gemmaPrompt)
                } else {
                    // No LLM — format ML Kit results as a readable description
                    buildFallbackDescription(labels, objects, texts, prompt)
                }

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

        // Run all three concurrently
        val labelsDeferred = scope.async { runLabeler(image) }
        val objectsDeferred = scope.async { runObjectDetector(image) }
        val textsDeferred = scope.async { runTextRecognizer(image) }

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

    // ── Prompt / description builders ──────────────────────────────────────

    private fun buildDetectionContext(
        labels: List<String>,
        objects: List<String>,
        texts: List<String>
    ): String = buildString {
        if (labels.isNotEmpty()) {
            appendLine("Scene labels: ${labels.joinToString(", ")}")
        }
        if (objects.isNotEmpty()) {
            appendLine("Detected objects: ${objects.joinToString("; ")}")
        }
        if (texts.isNotEmpty()) {
            appendLine("Visible text: ${texts.joinToString(" | ")}")
        }
        if (isEmpty()) appendLine("No specific elements detected with high confidence.")
    }

    private fun buildFallbackDescription(
        labels: List<String>,
        objects: List<String>,
        texts: List<String>,
        prompt: String
    ): String = buildString {
        val mode = prompt.lowercase()

        when {
            mode.contains("text") || mode.contains("read") -> {
                if (texts.isEmpty()) {
                    append("No text detected in the image.")
                } else {
                    append("Text found: ")
                    append(texts.joinToString(". "))
                }
            }
            mode.contains("navig") || mode.contains("walk") -> {
                append("Scene: ")
                if (labels.isNotEmpty()) append(labels.take(3).map { it.substringBefore(" (") }.joinToString(", "))
                if (objects.isNotEmpty()) {
                    append(". Objects: ")
                    append(objects.take(4).joinToString("; "))
                }
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

    // ── generateText ──────────────────────────────────────────────────────

    private fun handleGenerateText(prompt: String, result: Result) {
        scope.launch {
            val model = llm
            if (model == null) {
                mainResult(result) {
                    it.error("MODEL_NOT_LOADED", "Gemma model not loaded. Download it from Settings.", null)
                }
                return@launch
            }
            try {
                val response = model.generateResponse(prompt)
                mainResult(result) { it.success(response) }
            } catch (e: Exception) {
                mainResult(result) {
                    it.error("INFERENCE_ERROR", e.message ?: "Generation failed", null)
                }
            }
        }
    }

    // ── unloadModel ───────────────────────────────────────────────────────

    private fun handleUnloadModel(result: Result) {
        scope.launch {
            try {
                llm?.close()
                llm = null
                mainResult(result) { it.success(true) }
            } catch (e: Exception) {
                mainResult(result) { it.error("UNLOAD_ERROR", e.message, null) }
            }
        }
    }

    // ── Utility ───────────────────────────────────────────────────────────

    private suspend fun mainResult(result: Result, block: (Result) -> Unit) =
        withContext(Dispatchers.Main) { block(result) }
}
