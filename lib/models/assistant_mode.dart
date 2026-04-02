enum AssistantMode { scene, navigation, text, objects, quick }

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
      case AssistantMode.scene:      return '🌍';
      case AssistantMode.navigation: return '🧭';
      case AssistantMode.text:       return '📖';
      case AssistantMode.objects:    return '🔍';
      case AssistantMode.quick:      return '⚡';
    }
  }

  String get prompt {
    switch (this) {
      case AssistantMode.scene:
        return "Describe this scene in detail for a visually impaired person. Include setting, objects, people, lighting, colors, and any visible text.";
      case AssistantMode.navigation:
        return "Analyze for safe navigation. Describe obstacles, hazards, clear pathways and distances. Prioritize safety.";
      case AssistantMode.text:
        return "Read and transcribe ALL text visible in this image including signs, labels and buttons.";
      case AssistantMode.objects:
        return "List all visible objects with positions. Format: Object - Position - Description.";
      case AssistantMode.quick:
        return "In one sentence, describe the most important thing a blind person needs to know.";
    }
  }
}
