import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/// Downloads the Gemma 2B IT CPU INT4 model for MediaPipe Tasks GenAI.
///
/// The model is a single ~1.5 GB .bin file in MediaPipe FlatBuffer format.
/// It is loaded by [MlcLlmPlugin] via the MediaPipe LlmInference API.
///
/// The app works WITHOUT this model — ML Kit handles image analysis offline
/// without any download.  Gemma is an enhancement that produces richer,
/// more natural-sounding descriptions.
///
/// Download source: Google AI Edge / MediaPipe model gallery
/// (publicly accessible, no authentication required)
class ModelDownloader {
  // Official Google AI Edge hosted Gemma 2B CPU INT4 task bundle.
  // This URL is from Google's MediaPipe documentation examples.
  static const String _modelUrl =
      'https://storage.googleapis.com/mediapipe-models/'
      'llm_inference/gemma-2b-it-cpu-int4/float32/1/gemma-2b-it-cpu-int4.bin';

  static const String _modelFileName = 'gemma-2b-it-cpu-int4.bin';
  static const String _modelFolder   = 'gemma-mediapipe-model';

  // ~1.5 GB — used for progress display only
  static const int _estimatedSize = 1500 * 1024 * 1024;

  static Future<bool> isModelDownloaded() async {
    final file = File(await _modelFilePath());
    return file.existsSync() && file.lengthSync() > 100 * 1024 * 1024;
  }

  static Future<String> getModelPath() async {
    // The plugin accepts either a file path or a directory path.
    // Return the directory so the plugin can glob for *.bin / *.task.
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$_modelFolder';
  }

  static Future<String> _modelFilePath() async {
    final dir = await getModelPath();
    return '$dir/$_modelFileName';
  }

  static int getTotalSize() => _estimatedSize;

  static Stream<DownloadProgress> downloadModel() async* {
    final modelPath  = await getModelPath();
    final filePath   = await _modelFilePath();
    final modelDir   = Directory(modelPath);
    final outFile    = File(filePath);

    if (!await modelDir.exists()) await modelDir.create(recursive: true);

    // Resume download if partial file exists
    final existingBytes = await outFile.exists() ? await outFile.length() : 0;

    if (existingBytes > 100 * 1024 * 1024) {
      // Already downloaded
      yield DownloadProgress(
        progress: 1.0,
        status: 'Already downloaded',
        downloadedBytes: existingBytes,
        totalBytes: _estimatedSize,
      );
      return;
    }

    yield DownloadProgress(
      progress: 0.0,
      status: 'Connecting…',
      downloadedBytes: 0,
      totalBytes: _estimatedSize,
    );

    final request = http.Request('GET', Uri.parse(_modelUrl));
    if (existingBytes > 0) {
      // Range request for resumption
      request.headers['Range'] = 'bytes=$existingBytes-';
    }

    final response = await http.Client().send(request);

    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }

    final totalBytes = (response.contentLength ?? _estimatedSize) + existingBytes;
    int downloaded   = existingBytes;

    final sink = outFile.openWrite(mode: existingBytes > 0 ? FileMode.append : FileMode.write);

    await for (final chunk in response.stream) {
      sink.add(chunk);
      downloaded += chunk.length;
      yield DownloadProgress(
        progress: (downloaded / totalBytes).clamp(0.0, 1.0),
        status: 'Downloading Gemma 2B…',
        downloadedBytes: downloaded,
        totalBytes: totalBytes,
      );
    }

    await sink.close();

    yield DownloadProgress(
      progress: 1.0,
      status: 'Download complete!',
      downloadedBytes: downloaded,
      totalBytes: downloaded,
    );
  }

  static Future<void> deleteModel() async {
    final dir = Directory(await getModelPath());
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

// ── Data classes ──────────────────────────────────────────────────────────────

class DownloadProgress {
  final double progress;
  final String status;
  final int downloadedBytes;
  final int totalBytes;

  const DownloadProgress({
    required this.progress,
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
  });

  String get downloadedMB => '${(downloadedBytes / 1024 / 1024).toStringAsFixed(0)} MB';
  String get totalMB      => '${(totalBytes      / 1024 / 1024).toStringAsFixed(0)} MB';
}

// ── Download screen ───────────────────────────────────────────────────────────

class ModelDownloadScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const ModelDownloadScreen({super.key, required this.onComplete});

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  DownloadProgress? _progress;
  String? _error;
  bool _skipped = false;

  @override
  void initState() {
    super.initState();
    _checkAndMaybeDownload();
  }

  Future<void> _checkAndMaybeDownload() async {
    if (await ModelDownloader.isModelDownloaded()) {
      widget.onComplete();
    }
  }

  Future<void> _startDownload() async {
    setState(() { _error = null; _skipped = false; });
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

  void _skip() {
    setState(() => _skipped = true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final pct = ((_progress?.progress ?? 0) * 100).toInt();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.psychology_rounded, size: 64, color: Colors.blue),
              const SizedBox(height: 24),
              const Text(
                'Optional: Enhanced AI',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 12),
              const Text(
                'Download Gemma 2B for richer descriptions.\n'
                'The app already works without it via on-device ML.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 14),
              ),
              const SizedBox(height: 40),
              if (_progress != null) ...[
                LinearProgressIndicator(
                  value: _progress!.progress,
                  minHeight: 10,
                  backgroundColor: Colors.grey[800],
                ),
                const SizedBox(height: 12),
                Text(
                  '$pct%  ·  ${_progress!.downloadedMB} / ${_progress!.totalMB}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  _progress!.status,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
              ],
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _skip,
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white54),
                      child: const Text('Skip for now'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _progress == null || _error != null ? _startDownload : null,
                      child: Text(_error != null ? 'Retry' : 'Download (~1.5 GB)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'One-time download. Works offline forever after.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white24, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
