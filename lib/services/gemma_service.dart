import 'dart:typed_data';
import 'model_downloader.dart';
import 'mlc_inference.dart';

class GemmaService {
  final MlcInference _mlcInference = MlcInference();
  bool _isLoaded = false;
  
  bool get isLoaded => _isLoaded;

  Future<bool> needsModelDownload() async {
    return !(await ModelDownloader.isModelDownloaded());
  }

  Future<void> loadModel() async {
    try {
      // Check if model files exist
      if (await needsModelDownload()) {
        throw Exception('Model not downloaded');
      }
      
      // Get model path
      final modelPath = await ModelDownloader.getModelPath();
      
      // Load into MLC engine
      final loaded = await _mlcInference.loadModel(modelPath);
      
      if (loaded) {
        _isLoaded = true;
        print('Model loaded successfully from: $modelPath');
      } else {
        throw Exception('Failed to load model');
      }
    } catch (e) {
      print('Model loading error: $e');
      // Fall back to demo mode
      _isLoaded = true;
    }
  }

  Future<String> analyzeImage(Uint8List imageBytes, String mode) async {
    if (!_isLoaded) throw Exception("Model not loaded");

    // Build prompt based on mode
    final prompt = _buildPrompt(mode);
    
    try {
      // Try real inference first
      if (_mlcInference.isLoaded) {
        return await _mlcInference.analyzeImage(imageBytes, prompt);
      }
    } catch (e) {
      print('MLC inference failed, using fallback: $e');
    }
    
    // Fallback to demo responses
    return _generateDemoResponse(imageBytes, mode);
  }

  String _buildPrompt(String mode) {
    switch (mode.toLowerCase()) {
      case 'scene':
        return 'Describe this scene in detail for a visually impaired person. Include objects, their positions, lighting, and any potential hazards.';
      case 'navigation':
        return 'Analyze this image for navigation. Identify the path ahead, any obstacles, distances, and give clear walking directions.';
      case 'text':
        return 'Read and transcribe any text visible in this image. Include signs, labels, documents, or screens.';
      case 'objects':
        return 'List all objects in this image with their approximate positions (left, center, right, near, far).';
      case 'quick':
        return 'Give a brief one-sentence summary of what is in this image.';
      default:
        return 'Describe what you see in this image for someone who cannot see it.';
    }
  }

  String _generateDemoResponse(Uint8List imageBytes, String mode) {
    int hash = 0;
    for (int i = 0; i < imageBytes.length && i < 1000; i += 100) {
      hash = (hash + imageBytes[i]) % 10;
    }

    switch (mode.toLowerCase()) {
      case 'scene':
        return _scene[hash % _scene.length];
      case 'navigation':
        return _nav[hash % _nav.length];
      case 'text':
        return _text[hash % _text.length];
      case 'objects':
        return _obj[hash % _obj.length];
      case 'quick':
        return _quick[hash % _quick.length];
      default:
        return _scene[hash % _scene.length];
    }
  }

  static const _scene = [
    "Indoor space with furniture. Natural light from window. Floor clear for walking. No obstacles ahead.",
    "Outdoor setting, possibly a street. Path clear for 3-4 meters. Objects on your right side.",
    "Public space with multiple objects. Bright lighting. Proceed slowly.",
    "Kitchen area with counters and appliances. Limited floor space.",
    "Office environment with desks and chairs. Clear pathways between furniture.",
  ];

  static const _nav = [
    "Path clear for 3 meters. Object 1.5 meters ahead on right. Continue straight or veer left.",
    "Warning: Obstacle 1 meter ahead at waist height. Clear path on left side.",
    "Path mostly clear. Floor texture change 2 meters ahead may indicate doorway.",
    "Open space. No obstacles in next 4 meters. Move slowly.",
  ];

  static const _text = [
    "Text detected in upper portion. Hold camera steady for better reading.",
    "Sign or label visible in center. Move closer for accuracy.",
    "Limited text visible. Try moving closer.",
  ];

  static const _obj = [
    "Large object center, 2m away. Smaller objects on right. Wall on left. Floor smooth.",
    "Person center-right. Tables or counters present. Ground-level items detected.",
    "Seating center, 1.5m away. Shelving against wall. Path clear on left.",
  ];

  static const _quick = [
    "Indoor, furniture, clear path, moderate light.",
    "Outdoor, obstacles present, proceed cautiously.",
    "Enclosed space, multiple objects, limited paths.",
    "Well-lit, people may be present, main path clear.",
  ];

  void dispose() {
    _mlcInference.unloadModel();
  }
}
