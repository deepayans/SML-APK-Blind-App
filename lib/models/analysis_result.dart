import 'assistant_mode.dart';

class AnalysisResult {
  final String description;
  final AssistantMode mode;
  final DateTime timestamp;
  final String? imagePath;

  AnalysisResult({
    required this.description,
    required this.mode,
    required this.timestamp,
    this.imagePath,
  });

  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) return "Just now";
    if (difference.inMinutes < 60) return "${difference.inMinutes}m ago";
    if (difference.inHours < 24) return "${difference.inHours}h ago";
    return "${difference.inDays}d ago";
  }
}
