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
        return "Describe this scene in detail for a visually impaired person. Include the overall setting, layout, notable objects, people, lighting, colors, and any visible text or signs.";
      case AssistantMode.navigation:
        return "Analyze this image for safe navigation. Describe obstacles, hazards, clear pathways, doorways, and distance estimates. Prioritize safety information.";
      case AssistantMode.text:
        return "Read and transcribe ALL text visible in this image including signs, labels, screens, documents, and buttons. Note the location of each text element.";
      case AssistantMode.objects:
        return "List all objects visible with their positions. Format: [Object] - [Position] - [Description]. Positions: left, right, center, near, far.";
      case AssistantMode.quick:
        return "In one or two sentences, describe the most important elements a blind person needs to know about this image.";
    }
  }
}
