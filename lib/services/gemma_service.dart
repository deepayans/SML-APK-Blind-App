import 'dart:typed_data';
import 'model_downloader.dart';
import 'mlc_inference.dart';

/// Wraps the MLC LLM inference channel to provide image analysis.
///
/// Renamed class kept as [GemmaService] to avoid cascading file renames,
/// but now backed by MiniCPM-V — a real Vision-Language Model that understands
/// both the image and the text prompt simultaneously.
///
/// Key fixes vs the original:
///   - No silent fallback to canned demo strings.
///     If inference fails the error propagates so the UI can tell the user.
///   - Prompt building delegated to [_buildPrompt] as before, but these
///     prompts are now actually processed against the real image.
///   - [_mlcInference.isLoaded] is the sole gate; the demo path is gone.
class GemmaService {
  final MlcInference _mlcInference = MlcInference();
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  Future<bool> needsModelDownload() async =>
      !(await ModelDownloader.isModelDownloaded());

  Future<void> loadModel() async {
    if (await needsModelDownload()) {
      throw Exception(
          'Model not downloaded. Download it first via the setup screen.');
    }

    final modelPath = await ModelDownloader.getModelPath();
    final loaded = await _mlcInference.loadModel(modelPath);

    if (!loaded) {
      // loadModel returns false only when the platform channel itself fails
      // (e.g. wrong ABI, missing .so).  Throw a clear message.
      throw Exception(
          'MLCEngine failed to load the model from $modelPath. '
          'Ensure the compiled .so is present and the device is arm64.');
    }

    _isLoaded = true;
  }

  /// Analyse [imageBytes] according to [mode].
  ///
  /// Throws on failure — the caller ([AssistantProvider]) catches and
  /// surfaces the error to the user via TTS + status text.
  Future<String> analyzeImage(Uint8List imageBytes, String mode) async {
    if (!_isLoaded) throw Exception('Model not loaded. Call loadModel() first.');
    if (!_mlcInference.isLoaded) {
      throw Exception('Native MLC engine not ready.');
    }

    final prompt = _buildPrompt(mode);
    return await _mlcInference.analyzeImage(imageBytes, prompt);
  }

  String _buildPrompt(String mode) {
    switch (mode.toLowerCase()) {
      case 'scene':
        return 'Describe this scene in detail for a visually impaired person. '
            'Include all visible objects, their positions (left, right, centre, '
            'near, far), lighting conditions, and any potential hazards.';
      case 'navigation':
        return 'Analyse this image for safe navigation. Identify the clear path '
            'ahead, any obstacles or hazards with their positions and approximate '
            'distances, and give concise walking directions.';
      case 'text':
        return 'Read and transcribe every piece of text visible in this image. '
            'Include signs, labels, screens, documents, and handwriting.';
      case 'objects':
        return 'List every distinct object visible in this image. '
            'For each, state its approximate position (left/centre/right, '
            'near/far) and a brief description.';
      case 'quick':
        return 'In one or two sentences, tell a blind person the single most '
            'important thing they need to know about this image right now.';
      default:
        return 'Describe what you see in this image for someone who cannot see it.';
    }
  }

  void dispose() {
    _mlcInference.unloadModel();
  }
}
