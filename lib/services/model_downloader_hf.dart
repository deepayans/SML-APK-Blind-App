import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/// Downloads Gemma model directly from Hugging Face
/// First launch: Downloads model (needs internet)
/// After that: Works 100% offline forever
class ModelDownloader {
  // Hugging Face model - public, free, no personal hosting!
  static const String HF_REPO = 'mlc-ai/gemma-3-4b-it-q4f16_1-MLC';
  static const String HF_BASE = 'https://huggingface.co/$HF_REPO/resolve/main';
  
  // Files to download (total ~2.5GB)
  static const List<ModelFile> MODEL_FILES = [
    ModelFile('mlc-chat-config.json', 1024),           // ~1KB
    ModelFile('ndarray-cache.json', 50 * 1024),        // ~50KB
    ModelFile('tokenizer.json', 5 * 1024 * 1024),      // ~5MB
    ModelFile('tokenizer_config.json', 2 * 1024),      // ~2KB
    ModelFile('params_shard_0.bin', 700 * 1024 * 1024), // ~700MB
    ModelFile('params_shard_1.bin', 700 * 1024 * 1024), // ~700MB
    ModelFile('params_shard_2.bin', 700 * 1024 * 1024), // ~700MB
    ModelFile('params_shard_3.bin', 400 * 1024 * 1024), // ~400MB
  ];
  
  static const String MODEL_FOLDER = 'gemma-mlc-model';

  /// Check if model is already downloaded
  static Future<bool> isModelDownloaded() async {
    final modelPath = await getModelPath();
    final modelDir = Directory(modelPath);
    
    if (!await modelDir.exists()) return false;
    
    // Check if all required files exist
    for (final file in MODEL_FILES) {
      final filePath = '$modelPath/${file.name}';
      if (!await File(filePath).exists()) return false;
    }
    
    return true;
  }

  /// Get the path where model is stored
  static Future<String> getModelPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$MODEL_FOLDER';
  }

  /// Get total download size in bytes
  static int getTotalSize() {
    return MODEL_FILES.fold(0, (sum, file) => sum + file.estimatedSize);
  }

  /// Download all model files from Hugging Face
  /// Yields progress (0.0 to 1.0)
  static Stream<DownloadProgress> downloadModel() async* {
    final modelPath = await getModelPath();
    final modelDir = Directory(modelPath);
    
    // Create model directory
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    
    final totalSize = getTotalSize();
    int downloadedTotal = 0;
    
    for (int i = 0; i < MODEL_FILES.length; i++) {
      final file = MODEL_FILES[i];
      final filePath = '$modelPath/${file.name}';
      final outFile = File(filePath);
      
      // Skip if already downloaded
      if (await outFile.exists()) {
        final existingSize = await outFile.length();
        if (existingSize > 0) {
          downloadedTotal += existingSize;
          yield DownloadProgress(
            progress: downloadedTotal / totalSize,
            currentFile: file.name,
            fileIndex: i + 1,
            totalFiles: MODEL_FILES.length,
            status: 'Skipping ${file.name} (already exists)',
          );
          continue;
        }
      }
      
      // Download file
      final url = '$HF_BASE/${file.name}';
      
      yield DownloadProgress(
        progress: downloadedTotal / totalSize,
        currentFile: file.name,
        fileIndex: i + 1,
        totalFiles: MODEL_FILES.length,
        status: 'Downloading ${file.name}...',
      );
      
      try {
        final request = http.Request('GET', Uri.parse(url));
        final response = await http.Client().send(request);
        
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        
        final sink = outFile.openWrite();
        int fileDownloaded = 0;
        
        await for (final chunk in response.stream) {
          sink.add(chunk);
          fileDownloaded += chunk.length;
          downloadedTotal += chunk.length;
          
          yield DownloadProgress(
            progress: downloadedTotal / totalSize,
            currentFile: file.name,
            fileIndex: i + 1,
            totalFiles: MODEL_FILES.length,
            status: 'Downloading ${file.name}...',
            fileProgress: fileDownloaded / file.estimatedSize,
          );
        }
        
        await sink.close();
        
      } catch (e) {
        // Delete partial file on error
        if (await outFile.exists()) {
          await outFile.delete();
        }
        rethrow;
      }
    }
    
    yield DownloadProgress(
      progress: 1.0,
      currentFile: 'Complete',
      fileIndex: MODEL_FILES.length,
      totalFiles: MODEL_FILES.length,
      status: 'Download complete! AI ready for offline use.',
    );
  }

  /// Delete downloaded model to free space
  static Future<void> deleteModel() async {
    final modelPath = await getModelPath();
    final modelDir = Directory(modelPath);
    if (await modelDir.exists()) {
      await modelDir.delete(recursive: true);
    }
  }
  
  /// Get current download size on disk
  static Future<int> getDownloadedSize() async {
    final modelPath = await getModelPath();
    final modelDir = Directory(modelPath);
    
    if (!await modelDir.exists()) return 0;
    
    int total = 0;
    await for (final entity in modelDir.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }
}

/// Model file info
class ModelFile {
  final String name;
  final int estimatedSize;
  
  const ModelFile(this.name, this.estimatedSize);
}

/// Download progress info
class DownloadProgress {
  final double progress;        // 0.0 to 1.0
  final String currentFile;
  final int fileIndex;
  final int totalFiles;
  final String status;
  final double? fileProgress;   // Progress of current file
  
  const DownloadProgress({
    required this.progress,
    required this.currentFile,
    required this.fileIndex,
    required this.totalFiles,
    required this.status,
    this.fileProgress,
  });
}

/// Beautiful download screen with progress
class ModelDownloadScreen extends StatefulWidget {
  final VoidCallback onComplete;
  
  const ModelDownloadScreen({super.key, required this.onComplete});

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  DownloadProgress? _progress;
  bool _downloading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _error = null;
    });

    try {
      await for (final progress in ModelDownloader.downloadModel()) {
        if (!mounted) return;
        setState(() => _progress = progress);
        
        if (progress.progress >= 1.0) {
          await Future.delayed(const Duration(milliseconds: 500));
          widget.onComplete();
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Download failed: $e\n\nPlease check your internet connection and try again.';
        _downloading = false;
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final totalSize = ModelDownloader.getTotalSize();
    final downloadedSize = ((_progress?.progress ?? 0) * totalSize).toInt();
    
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon with animation
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.psychology_rounded,
                  size: 60,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 32),
              
              // Title
              const Text(
                'Setting Up AI Assistant',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              
              // Subtitle
              Text(
                'Downloading AI model for offline use',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(height: 48),
              
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress?.progress ?? 0,
                  backgroundColor: Colors.grey[800],
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                  minHeight: 12,
                ),
              ),
              const SizedBox(height: 16),
              
              // Progress text
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${((_progress?.progress ?? 0) * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  Text(
                    '${_formatSize(downloadedSize)} / ${_formatSize(totalSize)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Current file status
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _downloading ? Icons.downloading : Icons.check_circle,
                          color: _downloading ? Colors.orange : Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _progress?.status ?? 'Preparing...',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_progress != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'File ${_progress!.fileIndex} of ${_progress!.totalFiles}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              
              // Error message
              if (_error != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _startDownload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry Download'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 48),
              
              // Info text
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.blue,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'One-time download (~2.5 GB)\nAfter this, the app works completely offline!',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[300],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
