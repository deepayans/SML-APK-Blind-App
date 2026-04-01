package com.example.vision_assistant

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.*
import java.io.File
import java.io.ByteArrayOutputStream
import ai.mlc.mlcllm.MLCEngine

class MlcLlmPlugin: FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var engine: MLCEngine? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "mlc_llm_channel")
        channel.setMethodCallHandler(this)
        context = binding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
        engine?.unload()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "loadModel" -> {
                val modelPath = call.argument<String>("modelPath")
                if (modelPath == null) {
                    result.error("INVALID_ARGUMENT", "modelPath is required", null)
                    return
                }
                loadModel(modelPath, result)
            }
            "analyzeImage" -> {
                val imageBytes = call.argument<ByteArray>("imageBytes")
                val prompt = call.argument<String>("prompt") ?: "Describe this image"
                if (imageBytes == null) {
                    result.error("INVALID_ARGUMENT", "imageBytes is required", null)
                    return
                }
                analyzeImage(imageBytes, prompt, result)
            }
            "generateText" -> {
                val prompt = call.argument<String>("prompt")
                if (prompt == null) {
                    result.error("INVALID_ARGUMENT", "prompt is required", null)
                    return
                }
                generateText(prompt, result)
            }
            "unloadModel" -> {
                unloadModel(result)
            }
            "isModelLoaded" -> {
                result.success(engine != null)
            }
            else -> result.notImplemented()
        }
    }

    private fun loadModel(modelPath: String, result: Result) {
        scope.launch {
            try {
                val modelDir = File(modelPath)
                if (!modelDir.exists()) {
                    withContext(Dispatchers.Main) {
                        result.error("MODEL_NOT_FOUND", "Model directory not found: $modelPath", null)
                    }
                    return@launch
                }

                // Initialize MLC Engine
                engine = MLCEngine()
                engine?.reload(modelPath)
                
                withContext(Dispatchers.Main) {
                    result.success(true)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("LOAD_ERROR", "Failed to load model: ${e.message}", null)
                }
            }
        }
    }

    private fun analyzeImage(imageBytes: ByteArray, prompt: String, result: Result) {
        scope.launch {
            try {
                if (engine == null) {
                    withContext(Dispatchers.Main) {
                        result.error("MODEL_NOT_LOADED", "Model not loaded", null)
                    }
                    return@launch
                }

                // Decode image
                val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                if (bitmap == null) {
                    withContext(Dispatchers.Main) {
                        result.error("IMAGE_ERROR", "Failed to decode image", null)
                    }
                    return@launch
                }

                // Resize for model (Gemma uses 224x224 or 448x448)
                val resized = Bitmap.createScaledBitmap(bitmap, 448, 448, true)
                
                // Convert to base64 for model input
                val stream = ByteArrayOutputStream()
                resized.compress(Bitmap.CompressFormat.JPEG, 85, stream)
                val imageBase64 = Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)

                // Build vision prompt for Gemma
                val visionPrompt = buildVisionPrompt(prompt, imageBase64)
                
                // Generate response
                val response = engine?.chat?.completions?.create(
                    messages = listOf(
                        mapOf("role" to "user", "content" to visionPrompt)
                    ),
                    maxTokens = 300,
                    temperature = 0.3
                )

                val text = response?.choices?.firstOrNull()?.message?.content ?: "No response generated"

                bitmap.recycle()
                resized.recycle()

                withContext(Dispatchers.Main) {
                    result.success(text)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("INFERENCE_ERROR", "Inference failed: ${e.message}", null)
                }
            }
        }
    }

    private fun buildVisionPrompt(userPrompt: String, imageBase64: String): String {
        return """<start_of_turn>user
<image>$imageBase64</image>

You are a vision assistant for visually impaired users. Analyze the image and respond to: $userPrompt

Provide clear, helpful descriptions including:
- What is in the scene
- Object positions (left, right, center, near, far)
- Any obstacles or hazards
- Text or signs if visible
- Navigation guidance if relevant

Be concise but thorough.<end_of_turn>
<start_of_turn>model
"""
    }

    private fun generateText(prompt: String, result: Result) {
        scope.launch {
            try {
                if (engine == null) {
                    withContext(Dispatchers.Main) {
                        result.error("MODEL_NOT_LOADED", "Model not loaded", null)
                    }
                    return@launch
                }

                val response = engine?.chat?.completions?.create(
                    messages = listOf(
                        mapOf("role" to "user", "content" to prompt)
                    ),
                    maxTokens = 200,
                    temperature = 0.7
                )

                val text = response?.choices?.firstOrNull()?.message?.content ?: "No response"

                withContext(Dispatchers.Main) {
                    result.success(text)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("INFERENCE_ERROR", "Generation failed: ${e.message}", null)
                }
            }
        }
    }

    private fun unloadModel(result: Result) {
        scope.launch {
            try {
                engine?.unload()
                engine = null
                withContext(Dispatchers.Main) {
                    result.success(true)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("UNLOAD_ERROR", "Failed to unload: ${e.message}", null)
                }
            }
        }
    }
}
