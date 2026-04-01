import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/assistant_provider.dart';
import '../models/analysis_result.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("History")),
      body: Consumer<AssistantProvider>(
        builder: (context, provider, child) {
          final history = provider.history;

          if (history.isEmpty) {
            return const Center(
              child: Text("No history yet.\nTap the camera button to start.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: Colors.white70)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final result = history[index];
              return _HistoryCard(result: result);
            },
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final AnalysisResult result;

  const _HistoryCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "${result.mode.icon} ${result.mode.displayName}",
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
                Text(result.timeAgo,
                    style: const TextStyle(fontSize: 14, color: Colors.white54)),
              ],
            ),
            const SizedBox(height: 8),
            Text(result.description,
                style: const TextStyle(fontSize: 16, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
