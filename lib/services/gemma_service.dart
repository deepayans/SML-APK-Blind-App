import 'dart:typed_data';
import 'dart:math';

/// GemmaService — Vision AI interface
///
/// CURRENT MODE: Demo (simulated responses)
/// This builds and runs without any native dependencies so the APK compiles
/// cleanly on GitHub Actions CI.
///
/// TO ENABLE REAL ON-DEVICE INFERENCE:
/// Replace the body of analyzeImage() with MLC LLM or MediaPipe calls.
/// See: https://huggingface.co/mlc-ai/gemma-3-4b-it-q4f16_1-MLC
class GemmaService {
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  Future<void> loadModel() async {
    // Simulates model loading delay
    await Future.delayed(const Duration(seconds: 2));
    _isLoaded = true;
  }

  Future<String> analyzeImage(Uint8List imageBytes, String prompt) async {
    if (!_isLoaded) throw Exception("Model not loaded");
    // Add a small delay to simulate inference time
    await Future.delayed(const Duration(milliseconds: 800));
    return _generateDemoResponse(prompt);
  }

  String _generateDemoResponse(String prompt) {
    final random = Random();

    if (prompt.contains("scene") || prompt.contains("describe")) {
      final scenes = [
        "You are in what appears to be a living room. There is a couch directly ahead, about 3 meters away. To your left is a window with natural light coming through. A coffee table is positioned between you and the couch.",
        "This looks like an outdoor street scene. There is a sidewalk extending forward. On your right side, there are parked cars. Trees line the left side of the path.",
        "You appear to be in a kitchen area. Counter surfaces are visible to your right with what looks like a sink. Cabinets are mounted on the wall above.",
      ];
      return scenes[random.nextInt(scenes.length)];
    }

    if (prompt.contains("navigate") || prompt.contains("obstacle")) {
      final navigation = [
        "Clear path ahead for approximately 4 meters. Caution: There appears to be a chair slightly to your right at about 2 meters. The floor is level with no steps detected.",
        "Warning: Obstacle detected about 1 meter ahead, appears to be a table. Recommend moving to your left where the path appears clear.",
        "The path ahead is mostly clear. Note: A rug or mat is on the floor starting about 1 meter ahead.",
      ];
      return navigation[random.nextInt(navigation.length)];
    }

    if (prompt.contains("text") || prompt.contains("read")) {
      final texts = [
        "Text detected:\n- Center: EXIT sign in green letters\n- Right side: Room 204 on a door placard",
        "Visible text:\n- Top: Store sign reading COFFEE SHOP\n- Window: OPEN sign",
        "No clear text detected in this image.",
      ];
      return texts[random.nextInt(texts.length)];
    }

    if (prompt.contains("object") || prompt.contains("find")) {
      final objects = [
        "Objects detected:\n• Chair - center, 2m away\n• Table - right, 1.5m\n• Lamp - far left\n• Plant - right corner",
        "Objects detected:\n• Car - left, parked\n• Bicycle - right, against wall\n• Bench - center far\n• Tree - left",
      ];
      return objects[random.nextInt(objects.length)];
    }

    if (prompt.contains("quick")) {
      final quick = [
        "An indoor room with furniture including a couch and table, natural lighting.",
        "An outdoor sidewalk with trees and parked cars, clear path ahead.",
        "A kitchen space with counters and appliances.",
      ];
      return quick[random.nextInt(quick.length)];
    }

    return "I can see a scene in front of you. For more specific information, try using Scene, Navigation, Text, or Objects mode.";
  }

  void dispose() {}
}
