import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/// Downloads MiniCPM-V-2_6-q4f16_1-MLC from Hugging Face.
///
/// MiniCPM-V is a genuine Vision-Language Model (VLM) compiled with MLC LLM.
/// Unlike Gemma-3-4B (text-only), it accepts image input through the MLC
/// runtime's vision encoder and produces real, image-grounded descriptions.
///
/// Model: openbmb/MiniCPM-V-2_6-q4f16_1-MLC  (~2.3 GB total)
/// Compiled for: arm64-v8a Android, MLC LLM runtime
class ModelDownloader {
  static const String _hfRepo = 'mlc-ai/MiniCPM-V-2_6-q4f16_1-MLC';
  static const String _hfBase =
      'https://huggingface.co/$_hfRepo/resolve/main';

  /// Files required by the MLC runtime.
  /// Sizes are conservative estimates used only for progress display.
  static const List<ModelFile> modelFiles = [
    // Config + tokenizer (small)
    ModelFile('mlc-chat-config.json',    5  * 1024),
    ModelFile('ndarray-cache.json',      80 * 1024),
    ModelFile('tokenizer.json',          4  * 1024 * 1024),
    ModelFile('tokenizer_config.json',   5  * 1024),
    ModelFile('tokenizer.model',         2  * 1024 * 1024),
    // Compiled model library (.so) — vision encoder + language model
    ModelFile('lib/libminicpmv.so',      45 * 1024 * 1024),
    // Weight shards (~2.2 GB total for q4f16_1)
    ModelFile('params_shard_0.bin',      500 * 1024 * 1024),
    ModelFile('params_shard_1.bin',      500 * 1024 * 1024),
    ModelFile('params_shard_2.bin',      500 * 1024 * 1024),
    ModelFile('params_shard_3.bin',      500 * 1024 * 1024),
    ModelFile('params_shard_4.bin',      230 * 1024 * 1024),
  ];

  static const String _modelFolder = 'minicpmv-mlc-model';

  static Future<bool> isModelDownloaded() async {
    final modelPath = await getModelPath();
    final modelDir = Directory(modelPath);
    if (!await modelDir.exists()) return false;
    for (final file in modelFiles) {
      final f = File('$modelPath/${file.name}');
      if (!await f.exists() || await f.length() == 0) return false;
    }
    return true;
  }

  static Future<String> getModelPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$_modelFolder';
  }

  static int getTotalSize() =>
      modelFiles.fold(0, (sum, f) => sum + f.estimatedSize);

  /// Streams download progress for each file.
  /// Already-downloaded files are skipped (resumable).
  static Stream<DownloadProgress> downloadModel() async* {
    final modelPath = await getModelPath();
    final modelDir = Directory(modelPath);
    if (!await modelDir.exists()) await modelDir.create(recursive: true);

    // Ensure sub-directories exist (e.g. lib/)
    await Directory('$modelPath/lib').create(recursive: true);

    final totalSize = getTotalSize();
    int downloadedTotal = 0;

    for (int i = 0; i < modelFiles.length; i++) {
      final file = modelFiles[i];
      final filePath = '$modelPath/${file.name}';
      final outFile = File(filePath);

      // Skip if already downloaded
      if (await outFile.exists() && await outFile.length() > 0) {
        downloadedTotal += await outFile.length();
        yield DownloadProgress(
          progress: downloadedTotal / totalSize,
          currentFile: file.name,
          fileIndex: i + 1,
          totalFiles: modelFiles.length,
          status: 'Already downloaded: ${file.name}',
        );
        continue;
      }

      yield DownloadProgress(
        progress: downloadedTotal / totalSize,
        currentFile: file.name,
        fileIndex: i + 1,
        totalFiles: modelFiles.length,
        status: 'Downloading ${file.name}…',
      );

      final uri = Uri.parse('$_hfBase/${file.name}');
      final request = http.Request('GET', uri);
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        throw Exception(
            'HTTP ${response.statusCode} downloading ${file.name}');
      }

      final sink = outFile.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedTotal += chunk.length;
        yield DownloadProgress(
          progress: (downloadedTotal / totalSize).clamp(0.0, 1.0),
          currentFile: file.name,
          fileIndex: i + 1,
          totalFiles: modelFiles.length,
          status: 'Downloading ${file.name}…',
        );
      }
      await sink.close();
    }

    yield DownloadProgress(
      progress: 1.0,
      currentFile: 'Complete',
      fileIndex: modelFiles.length,
      totalFiles: modelFiles.length,
      status: 'Download complete!',
    );
  }

  static Future<void> deleteModel() async {
    final modelDir = Directory(await getModelPath());
    if (await modelDir.exists()) await modelDir.delete(recursive: true);
  }
}

// ── Data classes ──────────────────────────────────────────────────────────────

class ModelFile {
  final String name;
  final int estimatedSize;
  const ModelFile(this.name, this.estimatedSize);
}

class DownloadProgress {
  final double progress;
  final String currentFile;
  final int fileIndex;
  final int totalFiles;
  final String status;

  const DownloadProgress({
    required this.progress,
    required this.currentFile,
    required this.fileIndex,
    required this.totalFiles,
    required this.status,
  });
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
          await Future.delayed(const Duration(milliseconds: 600));
          widget.onComplete();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = ModelDownloader.getTotalSize();
    final done = ((_progress?.progress ?? 0) * total).toInt();
    final pct = ((_progress?.progress ?? 0) * 100).toInt();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.psychology_rounded,
                  size: 64, color: Colors.blue),
              const SizedBox(height: 32),
              const Text(
                'Setting Up Vision AI',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'MiniCPM-V · On-device · No cloud',
                style: TextStyle(color: Colors.blue, fontSize: 13),
              ),
              const SizedBox(height: 48),
              LinearProgressIndicator(
                value: _progress?.progress ?? 0,
                minHeight: 12,
                backgroundColor: Colors.grey[800],
              ),
              const SizedBox(height: 16),
              Text(
                '$pct%  ·  '
                '${(done / 1024 / 1024).toStringAsFixed(0)} MB'
                ' / ${(total / 1024 / 1024).toStringAsFixed(0)} MB',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                _progress?.status ?? 'Preparing…',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              if (_progress != null && _progress!.totalFiles > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'File ${_progress!.fileIndex} of ${_progress!.totalFiles}',
                    style: const TextStyle(color: Colors.white24, fontSize: 11),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.4)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _startDownload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
              const SizedBox(height: 48),
              const Text(
                'One-time ~2.3 GB download.\nWorks fully offline afterwards.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white30, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
