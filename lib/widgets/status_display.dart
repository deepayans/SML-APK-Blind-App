import 'package:flutter/material.dart';
import '../models/analysis_result.dart';

class StatusDisplay extends StatelessWidget {
  final String statusMessage;
  final bool isProcessing;
  final bool isListening;
  final AnalysisResult? lastResult;

  const StatusDisplay({
    super.key,
    required this.statusMessage,
    this.isProcessing = false,
    this.isListening = false,
    this.lastResult,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isProcessing)
                Column(
                  children: [
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: CircularProgressIndicator(
                          strokeWidth: 6,
                          color: Theme.of(context).primaryColor),
                    ),
                    const SizedBox(height: 24),
                    const Text("Analyzing...",
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                  ],
                )
              else
                Text(statusMessage,
                    style: const TextStyle(fontSize: 22, height: 1.5),
                    textAlign: TextAlign.center),
              if (lastResult != null && !isProcessing)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      "${lastResult!.mode.name}  •  ${lastResult!.timeAgo}",
                      style: const TextStyle(
                          fontSize: 14, color: Colors.white70),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
