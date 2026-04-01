import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class ModelDownloader {
  static const String HF_REPO = 'mlc-ai/gemma-3-4b-it-q4f16_1-MLC';
  static const String HF_BASE = 'https://huggingface.co/$HF_REPO/resolve/main';
  
  static const List<ModelFile> MODEL_FILES = [
    ModelFile('mlc-chat-config.json', 1024),
    ModelFile('ndarray-cache.json', 50 * 1024),
    ModelFile('tokenizer.json', 5 * 1024 * 1024),
    ModelFile('tokenizer_config.json', 2 * 1024),
    ModelFile('params_shard_0.bin', 700 * 1024 * 1024),
    ModelFile('params_shard_1.bin', 700 * 1024 * 1024),
    ModelFile('params_shard_2.bin', 700 * 1024 * 1024),
    ModelFile('params_shard_3.bin', 400 * 1024 * 1024),
  ];
  
  static const String MODEL_FOLDER = 'gemma-mlc-model';

  static Future<bool> isModelDownloaded() async {
    final modelPath = await getModelPath();
    final modelDir = Directory(modelPath);
    if (!await modelDir.exists()) return false;
    for (final file in MODEL_FILES) {
      if (!await File('$modelPath/${file.name}').exists()) return false;
    }
    return true;
  }

  static Future<String> getModelPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$MODEL_FOLDER';
  }

  static int getTotalSize() => MODEL_FILES.fold(0, (sum, f) => sum + f.estimatedSize);

  static Stream<DownloadProgress> downloadModel() async* {
    final modelPath = await getModelPath();
    final modelDir = Directory(modelPath);
    if (!await modelDir.exists()) await modelDir.create(recursive: true);
    
    final totalSize = getTotalSize();
    int downloadedTotal = 0;
    
    for (int i = 0; i < MODEL_FILES.length; i++) {
      final file = MODEL_FILES[i];
      final filePath = '$modelPath/${file.name}';
      final outFile = File(filePath);
      
      if (await outFile.exists() && await outFile.length() > 0) {
        downloadedTotal += await outFile.length();
        yield DownloadProgress(
          progress: downloadedTotal / totalSize,
          currentFile: file.name,
          fileIndex: i + 1,
          totalFiles: MODEL_FILES.length,
          status: 'Skipping ${file.name}',
        );
        continue;
      }
      
      yield DownloadProgress(
        progress: downloadedTotal / totalSize,
        currentFile: file.name,
        fileIndex: i + 1,
        totalFiles: MODEL_FILES.length,
        status: 'Downloading ${file.name}...',
      );
      
      final response = await http.Client().send(
        http.Request('GET', Uri.parse('$HF_BASE/${file.name}')),
      );
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      
      final sink = outFile.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedTotal += chunk.length;
        yield DownloadProgress(
          progress: downloadedTotal / totalSize,
          currentFile: file.name,
          fileIndex: i + 1,
          totalFiles: MODEL_FILES.length,
          status: 'Downloading ${file.name}...',
        );
      }
      await sink.close();
    }
    yield DownloadProgress(
      progress: 1.0,
      currentFile: 'Complete',
      fileIndex: MODEL_FILES.length,
      totalFiles: MODEL_FILES.length,
      status: 'Download complete!',
    );
  }

  static Future<void> deleteModel() async {
    final modelDir = Directory(await getModelPath());
    if (await modelDir.exists()) await modelDir.delete(recursive: true);
  }
}

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
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = ModelDownloader.getTotalSize();
    final done = ((_progress?.progress ?? 0) * total).toInt();
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.psychology_rounded, size: 60, color: Colors.blue),
              const SizedBox(height: 32),
              const Text(
                'Setting Up AI',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 48),
              LinearProgressIndicator(value: _progress?.progress ?? 0, minHeight: 12),
              const SizedBox(height: 16),
              Text(
                '${((_progress?.progress ?? 0) * 100).toInt()}%  |  ${(done / 1024 / 1024).toStringAsFixed(0)} MB / ${(total / 1024 / 1024).toStringAsFixed(0)} MB',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Text(_progress?.status ?? 'Preparing...', style: const TextStyle(color: Colors.white54)),
              if (_error != null) ...[
                const SizedBox(height: 24),
                Text(_error!, style: const TextStyle(color: Colors.red)),
                ElevatedButton(onPressed: _startDownload, child: const Text('Retry')),
              ],
              const SizedBox(height: 48),
              const Text(
                'One-time 2.5GB download\nWorks offline after this!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
