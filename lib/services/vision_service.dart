import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class VisionService {
  Interpreter? _interpreter;

  Future<void> init() async {
    try {
      _interpreter = await Interpreter.fromAsset('models/mobilenet.tflite');
      print("✅ Vision model loaded");
    } catch (e) {
      print("❌ Model load error: $e");
    }
  }

  Future<String> analyzeImage(File imageFile) async {
    if (_interpreter == null) {
      return "Vision model not initialized";
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) return "Invalid image";

      final resized = img.copyResize(image, width: 224, height: 224);

      var input = List.generate(
        1,
        (_) => List.generate(
          224,
          (y) => List.generate(
            224,
            (x) {
              final pixel = resized.getPixel(x, y);
              return [
                img.getRed(pixel) / 255.0,
                img.getGreen(pixel) / 255.0,
                img.getBlue(pixel) / 255.0,
              ];
            },
          ),
        ),
      );

      var output = List.generate(1, (_) => List.filled(1001, 0.0));

      _interpreter!.run(input, output);

      int maxIndex = 0;
      double maxScore = 0;

      for (int i = 0; i < 1001; i++) {
        if (output[0][i] > maxScore) {
          maxScore = output[0][i];
          maxIndex = i;
        }
      }

      print("🧠 Prediction index: $maxIndex (score: $maxScore)");

      return "Object index $maxIndex detected";

    } catch (e) {
      print("❌ Vision error: $e");
      return "Error analyzing image";
    }
  }
}
