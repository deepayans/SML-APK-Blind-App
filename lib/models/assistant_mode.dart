enum AssistantMode {
  scene,
  navigation,
  text,
  objects,
  quick,
}

extension AssistantModeExtension on AssistantMode {
  String get displayName {
    switch (this) {
      case AssistantMode.scene: return "Scene Description";
      case AssistantMode.navigation: return "Navigation";
      case AssistantMode.text: return "Text Reading";
      case AssistantMode.objects: return "Object Finding";
      case AssistantMode.quick: return "Quick Summary";
    }
  }

  String get shortName {
    switch (this) {
      case AssistantMode.scene: return "Scene";
      case AssistantMode.navigation: return "Navigate";
      case AssistantMode.text: return "Read";
      case AssistantMode.objects: return "Objects";
      case AssistantMode.quick: return "Quick";
    }
  }

  String get icon {
    switch (this) {
      case AssistantMode.scene: return "🏠";
      case AssistantMode.navigation: return "🚶";
      case AssistantMode.text: return "📖";
      case AssistantMode.objects: return "🔍";
      case AssistantMode.quick: return "⚡";
    }
  }

  String get prompt {
    switch (this) {
      case AssistantMode.scene:
        return '''Describe this scene in detail for a visually impaired person.
Include: the overall setting, layout of the space, notable objects, people present,
lighting conditions, colors, and any text or signs visible.
Be clear, organized, and helpful for navigation.''';

      case AssistantMode.navigation:
        return '''Analyze this image for a visually impaired person who needs to navigate safely.
Describe:
1. Any obstacles or hazards (furniture, objects on floor, stairs, uneven surfaces)
2. Clear pathways and their directions
3. Doorways, exits, or openings
4. Distance estimates when possible
5. Warnings about any potential dangers
Be concise and prioritize safety information.''';

      case AssistantMode.text:
        return '''Read and transcribe ALL text visible in this image.
Include: signs, labels, screens, documents, price tags, buttons, and any written content.
Format the text clearly, indicating where each piece of text is located.
If text is partially visible or unclear, note that.''';

      case AssistantMode.objects:
        return '''List all objects visible in this image with their approximate positions.
Format as: [Object] - [Position] - [Brief description]
Positions: left, right, center, top, bottom, near, far, foreground, background.
Include people, furniture, devices, and any notable items.''';

      case AssistantMode.quick:
        return '''In one or two sentences, describe what is in this image.
Focus on the most important elements a blind person would need to know.''';
    }
  }
}
