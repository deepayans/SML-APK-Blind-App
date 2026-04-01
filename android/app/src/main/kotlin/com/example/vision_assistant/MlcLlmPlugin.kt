package com.example.vision_assistant

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.*
import java.io.ByteArrayOutputStream
import java.io.File

// MLC LLM Android runtime (com.github.mlc-ai:mlc-llm-android via JitPack / maven.mlc.ai)
import ai.mlc.mlcllm.MLCEngine
import ai.mlc.mlcllm.OpenAIProtocol

private const val TAG = "MlcLlmPlugin"

class MlcLlmPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    // MLCEngine is NOT thread-safe — single-threaded dispatcher
    private var engine: MLCEngine? = null
    private val mlcThread = Dispatchers.IO.limitedParallelism(1)
    private val scope = CoroutineScope(mlcThread + SupervisorJob())

    // ── Flutter plugin lifecycle ─────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "mlc_llm_channel")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.launch { engine?.unload(); engine = null }
        scope.cancel()
    }

    // ── Method dispatch ──────────────────────────────────────────────────────

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
            "isModelLoaded" -> result.success(engine != null)
            "unloadModel"   -> handleUnloadModel(result)
            else            -> result.notImplemented()
        }
    }

    // ── loadModel ────────────────────────────────────────────────────────────
    //
    // MLCEngine.reload(path) reads mlc-chat-config.json from `path`, locates
    // the compiled .so via lib_local_path, and mmaps the weight shards.
    // `path` must be the directory saved by ModelDownloader.

    private fun handleLoadModel(modelPath: String, result: Result) {
        scope.launch {
            try {
                val dir = File(modelPath)
                if (!dir.exists() || !dir.isDirectory) {
                    return@launch mainResult(result) {
                        it.error("MODEL_NOT_FOUND", "Directory not found: $modelPath", null)
                    }
                }
                if (!File(dir, "mlc-chat-config.json").exists()) {
                    return@launch mainResult(result) {
                        it.error("MODEL_INVALID", "mlc-chat-config.json missing in $modelPath", null)
                    }
                }

                Log.i(TAG, "Loading model from: $modelPath")
                engine?.unload()

                val eng = MLCEngine()
                eng.reload(modelPath)
                engine = eng

                Log.i(TAG, "Model loaded successfully")
                mainResult(result) { it.success(true) }

            } catch (e: Exception) {
                Log.e(TAG, "loadModel failed", e)
                mainResult(result) {
                    it.error("LOAD_ERROR", "Failed to load model: ${e.message}", null)
                }
            }
        }
    }

    // ── analyzeImage ─────────────────────────────────────────────────────────
    //
    // MiniCPM-V (and other MLC-compiled VLMs) accept images via the OpenAI
    // vision message format:
    //   content: [
    //     { type: "image_url", image_url: { url: "data:image/jpeg;base64,<b64>" } },
    //     { type: "text",      text: "<prompt>" }
    //   ]
    //
    // The MLC runtime's vision encoder (SigLIP) tokenises the pixels before
    // passing them to the language model.  The base64 must be a JPEG/PNG.

    private fun handleAnalyzeImage(imageBytes: ByteArray, prompt: String, result: Result) {
        scope.launch {
            val eng = engine ?: return@launch mainResult(result) {
                it.error("MODEL_NOT_LOADED", "Call loadModel() before analyzeImage()", null)
            }

            try {
                // 1. Decode + resize/crop camera JPEG to 448x448
                val original = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                    ?: throw IllegalArgumentException("Could not decode image bytes")

                val resized = resizeAndCrop(original, 448)
                original.recycle()

                // 2. Re-encode to JPEG base64
                val bos = ByteArrayOutputStream()
                resized.compress(Bitmap.CompressFormat.JPEG, 90, bos)
                resized.recycle()
                val b64 = android.util.Base64.encodeToString(
                    bos.toByteArray(), android.util.Base64.NO_WRAP
                )

                // 3. Build OpenAI-compatible vision message
                val imageContent = OpenAIProtocol.ChatCompletionMessageContent(
                    type      = "image_url",
                    imageUrl  = OpenAIProtocol.ImageURL(url = "data:image/jpeg;base64,$b64")
                )
                val textContent = OpenAIProtocol.ChatCompletionMessageContent(
                    type = "text",
                    text = buildSystemPrompt(prompt)
                )

                val userMessage = OpenAIProtocol.ChatCompletionMessage(
                    role    = OpenAIProtocol.ChatCompletionRole.user,
                    content = listOf(imageContent, textContent)
                )

                // 4. Inference
                val request = OpenAIProtocol.ChatCompletionRequest(
                    messages    = listOf(userMessage),
                    max_tokens  = 350,
                    temperature = 0.3f,
                    stream      = false
                )

                val response = eng.chat.completions.create(request)
                val text = response.choices
                    ?.firstOrNull()
                    ?.message
                    ?.content
                    ?.trim()
                    ?: "No response generated"

                Log.d(TAG, "Inference result: $text")
                mainResult(result) { it.success(text) }

            } catch (e: Exception) {
                Log.e(TAG, "analyzeImage failed", e)
                mainResult(result) {
                    it.error("INFERENCE_ERROR", "Image analysis failed: ${e.message}", null)
                }
            }
        }
    }

    // ── generateText ─────────────────────────────────────────────────────────

    private fun handleGenerateText(prompt: String, result: Result) {
        scope.launch {
            val eng = engine ?: return@launch mainResult(result) {
                it.error("MODEL_NOT_LOADED", "Call loadModel() first", null)
            }
            try {
                val userMessage = OpenAIProtocol.ChatCompletionMessage(
                    role    = OpenAIProtocol.ChatCompletionRole.user,
                    content = prompt
                )
                val request = OpenAIProtocol.ChatCompletionRequest(
                    messages    = listOf(userMessage),
                    max_tokens  = 256,
                    temperature = 0.7f,
                    stream      = false
                )
                val response = eng.chat.completions.create(request)
                val text = response.choices
                    ?.firstOrNull()
                    ?.message
                    ?.content
                    ?.trim()
                    ?: "No response"

                mainResult(result) { it.success(text) }
            } catch (e: Exception) {
                Log.e(TAG, "generateText failed", e)
                mainResult(result) {
                    it.error("INFERENCE_ERROR", "Text generation failed: ${e.message}", null)
                }
            }
        }
    }

    // ── unloadModel ───────────────────────────────────────────────────────────

    private fun handleUnloadModel(result: Result) {
        scope.launch {
            try {
                engine?.unload()
                engine = null
                mainResult(result) { it.success(true) }
            } catch (e: Exception) {
                mainResult(result) {
                    it.error("UNLOAD_ERROR", "Unload failed: ${e.message}", null)
                }
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /**
     * Scale so the shorter side == [size], then centre-crop to [size]x[size].
     * Matches the preprocessing expected by MiniCPM-V's SigLIP vision encoder.
     */
    private fun resizeAndCrop(src: Bitmap, size: Int): Bitmap {
        val w = src.width.toFloat()
        val h = src.height.toFloat()
        val scale = size / minOf(w, h)
        val scaledW = (w * scale).toInt()
        val scaledH = (h * scale).toInt()

        val scaled  = Bitmap.createScaledBitmap(src, scaledW, scaledH, true)
        val x       = (scaledW - size) / 2
        val y       = (scaledH - size) / 2
        val cropped = Bitmap.createBitmap(scaled, x, y, size, size)
        if (cropped !== scaled) scaled.recycle()
        return cropped
    }

    /**
     * Wraps the analytical prompt in a system context for a blind user's assistant.
     */
    private fun buildSystemPrompt(userPrompt: String): String =
        "You are a vision assistant for a visually impaired person. " +
        "Analyse the image and respond to: $userPrompt\n" +
        "Be concise and specific. Include spatial positions (left, right, centre, " +
        "near, far). Mention hazards prominently."

    private suspend fun mainResult(result: Result, block: (Result) -> Unit) =
        withContext(Dispatchers.Main) { block(result) }
}
