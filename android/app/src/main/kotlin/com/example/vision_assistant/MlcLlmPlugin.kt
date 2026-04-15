package com.example.vision_assistant

import android.content.Context
import android.graphics.BitmapFactory
import android.util.Log
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInference.LlmInferenceOptions
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession.LlmInferenceSessionOptions
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.label.ImageLabeling
import com.google.mlkit.vision.label.defaults.ImageLabelerOptions
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
 *   • Object Detection  — finds objects and their bounding-box positions
 *   • Image Labeling    — identifies specific objects (person, chair, tv…)
 *   • Text Recognition  — reads visible text (OCR)
 *
 * Stage 2 — Gemma 3 1B via MediaPipe tasks-genai 0.10.22:
 *   • Session-based API: LlmInference (engine) + LlmInferenceSession (per request)
 *   • Prompt uses Gemma's required chat template (<start_of_turn>user/model)
 *   • Fully offline after the one-time ~555 MB download
 *
 * API note (tasks-genai 0.10.22+):
 *   The old llmInference.generateResponse(prompt) API was removed.
 *   Correct flow:
 *     val session = LlmInferenceSession.createFromOptions(llmInference, sessionOptions)
 *     session.addQueryChunk(prompt)
 *     val response = session.generateResponse()   // no arguments
 *     session.close()
 */
class MlcLlmPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    // All LLM work on a single-threaded dispatcher — LlmInference is NOT thread-safe.
    private val llmDispatcher = Dispatchers.IO.limitedParallelism(1)
    // ML Kit is thread-safe — runs on general IO pool.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // The model engine — initialised once in loadGemma(), reused across all requests.
    private var llmInference: LlmInference? = null

    // ── ML Kit detectors (lazy, reused) ───────────────────────────────────

    private val objectDetector by lazy {
        ObjectDetection.getClient(
            ObjectDetectorOptions.Builder()
                .setDetectorMode(ObjectDetectorOptions.SINGLE_IMAGE_MODE)
                .enableMultipleObjects()
                .build()
        )
    }

    private val imageLabeler by lazy {
        ImageLabeling.getClient(
            ImageLabelerOptions.Builder()
                .setConfidenceThreshold(0.6f)
                .build()
        )
    }

    private val textRecognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    // ── Plugin lifecycle ───────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "mlc_llm_channel")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.launch(llmDispatcher) {
            runCatching { llmInference?.close() }
            llmInference = null
        }
        scope.cancel()
    }

    // ── Method dispatch ────────────────────────────────────────────────────

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
                val prompt = call.argument<String>("prompt") ?: "Describe this image."
                analyzeImage(bytes, prompt, result)
            }
            "analyzeBurst" -> {
                val rawFrames = call.argument<List<Any>>("frames")
                    ?: return result.error("INVALID_ARGUMENT", "frames required", null)
                val frames = rawFrames.filterIsInstance<ByteArray>()
                if (frames.isEmpty()) return result.error("INVALID_ARGUMENT", "no valid frames", null)
                val prompt = call.argument<String>("prompt") ?: "Describe this image."
                analyzeBurst(frames, prompt, result)
            }
            "isModelLoaded" -> result.success(llmInference != null)
            "unloadModel"   -> unload(result)
            "generateText"  -> {
                val prompt = call.argument<String>("prompt")
                    ?: return result.error("INVALID_ARGUMENT", "prompt required", null)
                generateText(prompt, result)
            }
            else -> result.notImplemented()
        }
    }

    // ── Load Gemma engine ──────────────────────────────────────────────────

    private fun loadGemma(modelPath: String, result: Result) {
        scope.launch(llmDispatcher) {
            try {
                val file = findModelFile(modelPath)
                    ?: return@launch reply(result) {
                        it.error("MODEL_NOT_FOUND",
                            "No .task or .bin model file found in: $modelPath", null)
                    }

                Log.i(TAG, "Loading Gemma from: ${file.absolutePath}")
                runCatching { llmInference?.close() }

                // tasks-genai 0.10.22: engine-level options only contain model path
                // and token budget. Temperature / topK belong on LlmInferenceSessionOptions.
                val options = LlmInferenceOptions.builder()
                    .setModelPath(file.absolutePath)
                    .setMaxTokens(1024)
                    .build()

                llmInference = LlmInference.createFromOptions(context, options)
                Log.i(TAG, "Gemma engine loaded successfully")
                reply(result) { it.success(true) }

            } catch (e: Exception) {
                Log.e(TAG, "loadGemma failed: ${e.message}", e)
                reply(result) { it.error("LOAD_ERROR", e.message ?: "Load failed", null) }
            }
        }
    }

    private fun findModelFile(path: String): File? {
        val f = File(path)
        return when {
            f.isFile      -> f
            f.isDirectory -> f.listFiles()
                ?.firstOrNull { it.extension == "task" || it.extension == "bin" }
            else          -> null
        }
    }

    // ── analyzeImage: ML Kit → Gemma pipeline ─────────────────────────────

    private fun analyzeImage(imageBytes: ByteArray, prompt: String, result: Result) {
        scope.launch {
            try {
                val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                    ?: throw Exception("Could not decode image bytes.")

                val w = bitmap.width
                val h = bitmap.height
                val image = InputImage.fromBitmap(bitmap, 0)

                // Stage 1: ML Kit in parallel — all detectors are thread-safe.
                val objJob   = async { detectObjects(image, w, h) }
                val labelJob = async { labelImage(image) }
                val txtJob   = async { recognizeText(image) }
                val objects = objJob.await()
                val labels  = labelJob.await()
                val texts   = txtJob.await()
                bitmap.recycle()

                // Stage 2: Gemma via session on the single-threaded dispatcher.
                // If Gemma inference fails at runtime (OOM, model error, empty
                // response, etc.) we fall back to the ML Kit structured output
                // so the user always gets *something* spoken back.
                val response = withContext(llmDispatcher) {
                    val engine = llmInference
                    if (engine != null) {
                        try {
                            val gemmaResponse = runWithSession(engine) { session ->
                                // Use Gemma's chat template — required for instruction-tuned models.
                                session.addQueryChunk(buildGemmaPrompt(objects, labels, texts, prompt))
                                session.generateResponse()  // tasks-genai 0.10.22: no arguments
                            }
                            // Guard against empty / whitespace-only Gemma output
                            if (gemmaResponse.isNullOrBlank()) {
                                Log.w(TAG, "Gemma returned empty response — falling back to ML Kit")
                                buildFallback(objects, labels, texts, prompt)
                            } else {
                                gemmaResponse
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Gemma inference failed, falling back to ML Kit: ${e.message}", e)
                            buildFallback(objects, labels, texts, prompt)
                        }
                    } else {
                        // Gemma not yet loaded — return ML Kit structured output directly.
                        buildFallback(objects, labels, texts, prompt)
                    }
                }

                reply(result) { it.success(response.trim()) }

            } catch (e: Exception) {
                Log.e(TAG, "analyzeImage error: ${e.message}", e)
                reply(result) {
                    it.error("INFERENCE_ERROR", e.message ?: "Analysis failed", null)
                }
            }
        }
    }

    // ── analyzeBurst: multi-frame ML Kit → merge → Gemma ──────────────────

    /**
     * Burst analysis: runs ML Kit on every frame, deduplicates the detections
     * across all frames, then runs Gemma once on the merged result.
     *
     * More frames → more labels / text / object positions → richer output.
     */
    private fun analyzeBurst(frameList: List<ByteArray>, prompt: String, result: Result) {
        scope.launch {
            try {
                val bitmaps = frameList.mapNotNull { bytes ->
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                }
                if (bitmaps.isEmpty()) throw Exception("Could not decode any frames.")

                // Run ML Kit on every frame in parallel and accumulate results.
                val allLabels  = mutableSetOf<String>()
                val allObjects = mutableListOf<String>()
                val allTexts   = mutableSetOf<String>()

                val frameJobs = bitmaps.map { bitmap ->
                    async {
                        val w = bitmap.width
                        val h = bitmap.height
                        val image = InputImage.fromBitmap(bitmap, 0)
                        val o = async { detectObjects(image, w, h) }
                        val l = async { labelImage(image) }
                        val t = async { recognizeText(image) }
                        Triple(o.await(), l.await(), t.await())
                    }
                }
                frameJobs.forEach { job ->
                    val (objs, lbls, txts) = job.await()
                    allObjects.addAll(objs)
                    allLabels.addAll(lbls)
                    allTexts.addAll(txts)
                }
                bitmaps.forEach { it.recycle() }

                val uniqueObjects = allObjects.distinct().take(8)
                val uniqueLabels  = allLabels.toList().take(10)
                val uniqueTexts   = allTexts.toList().take(10)

                Log.i(TAG, "Burst merged: ${uniqueLabels.size} labels, " +
                        "${uniqueObjects.size} positions, ${uniqueTexts.size} texts")

                // Stage 2: single Gemma call on merged detections.
                val response = withContext(llmDispatcher) {
                    val engine = llmInference
                    if (engine != null) {
                        try {
                            val gemmaResponse = runWithSession(engine) { session ->
                                session.addQueryChunk(
                                    buildGemmaPrompt(uniqueObjects, uniqueLabels, uniqueTexts, prompt))
                                session.generateResponse()
                            }
                            if (gemmaResponse.isNullOrBlank()) {
                                Log.w(TAG, "Gemma empty on burst — falling back to ML Kit")
                                buildFallback(uniqueObjects, uniqueLabels, uniqueTexts, prompt)
                            } else gemmaResponse
                        } catch (e: Exception) {
                            Log.e(TAG, "Gemma burst inference failed: ${e.message}", e)
                            buildFallback(uniqueObjects, uniqueLabels, uniqueTexts, prompt)
                        }
                    } else {
                        buildFallback(uniqueObjects, uniqueLabels, uniqueTexts, prompt)
                    }
                }
                reply(result) { it.success(response.trim()) }

            } catch (e: Exception) {
                Log.e(TAG, "analyzeBurst error: ${e.message}", e)
                reply(result) {
                    it.error("INFERENCE_ERROR", e.message ?: "Burst analysis failed", null)
                }
            }
        }
    }

    /**
     * Creates a fresh [LlmInferenceSession], runs [block], then closes it.
     *
     * A new session per request prevents conversation history from bleeding
     * across unrelated scene descriptions.
     * Must be called on [llmDispatcher] — sessions are not thread-safe.
     */
    private fun runWithSession(engine: LlmInference, block: (LlmInferenceSession) -> String): String {
        val sessionOptions = LlmInferenceSessionOptions.builder()
            .setTopK(40)
            .setTemperature(0.7f)
            .build()
        val session = LlmInferenceSession.createFromOptions(engine, sessionOptions)
        return try {
            block(session)
        } finally {
            runCatching { session.close() }
        }
    }

    // ── Gemma 3 prompt template ────────────────────────────────────────────

    /**
     * Wraps the scene context and task in Gemma 3's required chat template.
     *
     * Format:
     *   <start_of_turn>user\n{text}<end_of_turn>\n<start_of_turn>model\n
     *
     * Without this template Gemma 3 instruction-tuned models produce
     * garbled, repetitive, or empty output.
     */
    private fun buildGemmaPrompt(objects: List<String>, labels: List<String>, texts: List<String>, task: String): String {
        val scene = buildString {
            if (labels.isNotEmpty())  appendLine("Identified: ${labels.joinToString(", ")}")
            if (objects.isNotEmpty()) appendLine("Object positions: ${objects.joinToString("; ")}")
            if (texts.isNotEmpty())   appendLine("Visible text: ${texts.joinToString(" | ")}")
            if (labels.isEmpty() && objects.isEmpty() && texts.isEmpty()) appendLine("Nothing detected by on-device vision.")
        }.trim()

        val userMessage = """
You are a vision assistant for a visually impaired person.
Respond in 2-3 sentences only. State positions (left, centre, right) and distance (near, far). Mention hazards first.

Scene:
$scene

Task: $task
        """.trimIndent()

        return "<start_of_turn>user\n$userMessage<end_of_turn>\n<start_of_turn>model\n"
    }

    // ── ML Kit helpers ─────────────────────────────────────────────────────

    /** Object Detection — returns spatial positions only (left/centre/right, near/far). */
    private suspend fun detectObjects(image: InputImage, w: Int, h: Int): List<String> =
        suspendCoroutine { cont ->
            objectDetector.process(image)
                .addOnSuccessListener { items ->
                    cont.resume(items.mapIndexed { i, obj ->
                        val cx = obj.boundingBox.exactCenterX()
                        val pos = when {
                            cx < w * 0.33f -> "left"
                            cx < w * 0.66f -> "centre"
                            else           -> "right"
                        }
                        val near = obj.boundingBox.height() > h * 0.4f
                        "object ${i + 1} at $pos${if (near) ", close" else ""}"
                    })
                }
                .addOnFailureListener { e ->
                    Log.w(TAG, "detectObjects failed (non-fatal): ${e.message}")
                    cont.resume(emptyList())
                }
        }

    /** Image Labeling — returns specific labels (person, chair, tv, …). */
    private suspend fun labelImage(image: InputImage): List<String> =
        suspendCoroutine { cont ->
            imageLabeler.process(image)
                .addOnSuccessListener { items ->
                    cont.resume(
                        items.take(8).map { it.text }
                    )
                }
                .addOnFailureListener { cont.resumeWithException(it) }
        }

    private suspend fun recognizeText(image: InputImage): List<String> =
        suspendCoroutine { cont ->
            textRecognizer.process(image)
                .addOnSuccessListener { vt ->
                    cont.resume(
                        vt.textBlocks
                            .flatMap { it.lines }
                            .map { it.text.trim() }
                            .filter { it.isNotBlank() }
                    )
                }
                .addOnFailureListener { e ->
                    Log.w(TAG, "recognizeText failed (non-fatal): ${e.message}")
                    cont.resume(emptyList())
                }
        }

    // ── ML Kit-only fallback (Gemma not yet loaded) ────────────────────────

    private fun buildFallback(objects: List<String>, labels: List<String>, texts: List<String>, prompt: String): String =
        buildString {
            val mode = prompt.lowercase()
            when {
                mode.contains("text") || mode.contains("read") -> {
                    if (texts.isEmpty()) append("No text visible in this image.")
                    else { append("Text: "); append(texts.joinToString(". ")) }
                }
                mode.contains("navig") || mode.contains("walk") -> {
                    if (objects.isEmpty()) append("Path appears clear. Proceed with caution.")
                    else {
                        if (labels.isNotEmpty()) {
                            append("Detected ahead: ${labels.take(5).joinToString(", ")}. ")
                        }
                        append("Positions: ${objects.take(5).joinToString("; ")}")
                    }
                }
                else -> {
                    if (labels.isNotEmpty()) {
                        append("Detected: ")
                        append(labels.take(6).joinToString(", "))
                        append(". ")
                    }
                    if (objects.isNotEmpty()) {
                        append("Positions: ")
                        append(objects.take(5).joinToString("; "))
                        append(". ")
                    }
                    if (texts.isNotEmpty()) {
                        append("Text: ")
                        append(texts.take(3).joinToString(". "))
                    }
                    if (isEmpty()) append("Nothing clearly detected. Move closer or try again.")
                }
            }
        }

    // ── generateText (voice commands, etc.) ───────────────────────────────

    private fun generateText(prompt: String, result: Result) {
        scope.launch(llmDispatcher) {
            val engine = llmInference ?: return@launch reply(result) {
                it.error("MODEL_NOT_LOADED", "Gemma not loaded yet.", null)
            }
            try {
                val response = runWithSession(engine) { session ->
                    session.addQueryChunk(
                        "<start_of_turn>user\n$prompt<end_of_turn>\n<start_of_turn>model\n"
                    )
                    session.generateResponse()
                }
                reply(result) { it.success(response.trim()) }
            } catch (e: Exception) {
                reply(result) { it.error("INFERENCE_ERROR", e.message ?: "Generation failed", null) }
            }
        }
    }

    // ── Unload ─────────────────────────────────────────────────────────────

    private fun unload(result: Result) {
        scope.launch(llmDispatcher) {
            try {
                runCatching { llmInference?.close() }
                llmInference = null
                reply(result) { it.success(true) }
            } catch (e: Exception) {
                reply(result) { it.error("UNLOAD_ERROR", e.message, null) }
            }
        }
    }

    private suspend fun reply(result: Result, block: (Result) -> Unit) =
        withContext(Dispatchers.Main) { block(result) }
}
