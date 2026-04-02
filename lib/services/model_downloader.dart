import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/// Downloads Gemma 2B IT CPU INT4 — the Small Language Model that powers
/// natural language descriptions in the app.
///
/// Source: Google AI Edge / MediaPipe model gallery (public, no auth needed)
/// Format: MediaPipe LlmInference .bin file
/// Size: ~1.5 GB (one-time download, works offline forever after)
class ModelDownloader {
  static const String _modelUrl =
      'https://storage.googleapis.com/mediapipe-models/'
      'llm_inference/gemma-2b-it-cpu-int4/float32/1/gemma-2b-it-cpu-int4.bin';

  static const String _modelFileName = 'gemma-2b-it-cpu-int4.bin';
  static const String _modelFolder   = 'gemma-mediapipe';

  // Approx size — used for progress display only
  static const int _approxBytes = 1500000000;

  static Future<String> getModelPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$_modelFolder';
  }

  static Future<String> _filePath() async =>
      '${await getModelPath()}/$_modelFileName';

  static Future<bool> isModelDownloaded() async {
    final file = File(await _filePath());
    // Must exist and be at least 1 GB to be considered complete
    return file.existsSync() && file.lengthSync() > 1000000000;
  }

  static int getTotalSize() => _approxBytes;

  static Stream<DownloadProgress> downloadModel() async* {
    final dir  = Directory(await getModelPath());
    final file = File(await _filePath());

    if (!await dir.exists()) await dir.create(recursive: true);

    // Resume support — send Range header if partial file exists
    final existing = file.existsSync() ? file.lengthSync() : 0;

    if (existing > 1000000000) {
      yield DownloadProgress(progress: 1.0, downloaded: existing,
          total: existing, status: 'Already downloaded');
      return;
    }

    yield DownloadProgress(progress: 0.0, downloaded: existing,
        total: _approxBytes, status: 'Connecting…');

    final request = http.Request('GET', Uri.parse(_modelUrl));
    if (existing > 0) request.headers['Range'] = 'bytes=$existing-';

    final response = await http.Client().send(request);
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }

    final total      = (response.contentLength ?? _approxBytes) + existing;
    int downloaded   = existing;
    final sink       = file.openWrite(
        mode: existing > 0 ? FileMode.append : FileMode.write);

    await for (final chunk in response.stream) {
      sink.add(chunk);
      downloaded += chunk.length;
      yield DownloadProgress(
        progress: (downloaded / total).clamp(0.0, 1.0),
        downloaded: downloaded,
        total: total,
        status: 'Downloading Gemma 2B…',
      );
    }
    await sink.close();

    yield DownloadProgress(progress: 1.0, downloaded: downloaded,
        total: downloaded, status: 'Complete!');
  }

  static Future<void> deleteModel() async {
    final dir = Directory(await getModelPath());
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

class DownloadProgress {
  final double progress;
  final int downloaded;
  final int total;
  final String status;
  const DownloadProgress({
    required this.progress,
    required this.downloaded,
    required this.total,
    required this.status,
  });
  String get downloadedMB => '${(downloaded / 1e6).toStringAsFixed(0)} MB';
  String get totalMB      => '${(total      / 1e6).toStringAsFixed(0)} MB';
}

// ── Mandatory first-launch download screen ────────────────────────────────────

class ModelDownloadScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const ModelDownloadScreen({super.key, required this.onComplete});

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  DownloadProgress? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    setState(() => _error = null);
    try {
      await for (final p in ModelDownloader.downloadModel()) {
        if (!mounted) return;
        setState(() => _progress = p);
        if (p.progress >= 1.0) {
          await Future.delayed(const Duration(milliseconds: 500));
          widget.onComplete();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = ((_progress?.progress ?? 0) * 100).toInt();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.psychology_rounded,
                    size: 48, color: Colors.blue),
              ),
              const SizedBox(height: 32),

              // Title
              const Text('Setting Up Vision AI',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold,
                    color: Colors.white),
                textAlign: TextAlign.center),
              const SizedBox(height: 12),

              // Subtitle
              const Text(
                'Downloading Gemma 2B — the Small Language Model\n'
                'that powers accurate scene descriptions.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 48),

              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress?.progress ?? 0,
                  minHeight: 10,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
              const SizedBox(height: 16),

              // Stats
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$pct%',
                      style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  Text(
                    '${_progress?.downloadedMB ?? "0 MB"}'
                    ' / ${_progress?.totalMB ?? "~1500 MB"}',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _progress?.status ?? 'Preparing…',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Column(children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _startDownload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ]),
                ),
              ],

              const SizedBox(height: 48),
              const Text(
                'One-time download · ~1.5 GB · WiFi recommended\n'
                'Works fully offline after this.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white24, fontSize: 12, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
