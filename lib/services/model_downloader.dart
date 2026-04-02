import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Downloads Gemma 2B IT CPU INT4 from Hugging Face.
///
/// Google removed the public GCS URL. The model now lives on Hugging Face
/// at google/gemma-2b-it-tflite and requires a Bearer token because the
/// Gemma licence must be accepted before downloading.
///
/// First-time setup:
///   1. Create a Hugging Face account at huggingface.co
///   2. Accept the Gemma licence at huggingface.co/google/gemma-2b-it-tflite
///   3. Generate a Read token at huggingface.co/settings/tokens
///   4. Enter the token in the app — it is stored locally and never sent
///      anywhere except to api.huggingface.co for the one-time download.
class ModelDownloader {
  static const String _modelUrl =
      'https://huggingface.co/google/gemma-2b-it-tflite/resolve/main/'
      'gemma-2b-it-cpu-int4.bin';

  static const String _modelFileName = 'gemma-2b-it-cpu-int4.bin';
  static const String _modelFolder   = 'gemma-mediapipe';
  static const String _hfTokenKey    = 'hf_token';

  static const int _approxBytes = 1500000000;

  // ── Token persistence ────────────────────────────────────────────────────

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hfTokenKey, token.trim());
  }

  static Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_hfTokenKey);
    return (t != null && t.isNotEmpty) ? t : null;
  }

  // ── Model path ───────────────────────────────────────────────────────────

  static Future<String> getModelPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$_modelFolder';
  }

  static Future<String> _filePath() async =>
      '${await getModelPath()}/$_modelFileName';

  static Future<bool> isModelDownloaded() async {
    final file = File(await _filePath());
    return file.existsSync() && file.lengthSync() > 1000000000;
  }

  static int getTotalSize() => _approxBytes;

  // ── Download ─────────────────────────────────────────────────────────────

  /// Downloads the model from Hugging Face using [hfToken].
  /// Supports resume — if a partial file exists a Range header is sent.
  static Stream<DownloadProgress> downloadModel(String hfToken) async* {
    final dir  = Directory(await getModelPath());
    final file = File(await _filePath());

    if (!await dir.exists()) await dir.create(recursive: true);

    final existing = file.existsSync() ? file.lengthSync() : 0;

    if (existing > 1000000000) {
      yield DownloadProgress(
          progress: 1.0, downloaded: existing,
          total: existing, status: 'Already downloaded');
      return;
    }

    yield DownloadProgress(
        progress: 0.0, downloaded: existing,
        total: _approxBytes, status: 'Connecting to Hugging Face…');

    final request = http.Request('GET', Uri.parse(_modelUrl));
    request.headers['Authorization'] = 'Bearer $hfToken';
    if (existing > 0) request.headers['Range'] = 'bytes=$existing-';

    final response = await http.Client().send(request);

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception(
          'Token rejected (HTTP ${response.statusCode}). '
          'Make sure you accepted the Gemma licence at '
          'huggingface.co/google/gemma-2b-it-tflite and the token has Read access.');
    }
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }

    final total    = (response.contentLength ?? _approxBytes) + existing;
    int downloaded = existing;
    final sink     = file.openWrite(
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

    // Save the token so the user never has to enter it again
    await saveToken(hfToken);

    yield DownloadProgress(
        progress: 1.0, downloaded: downloaded,
        total: downloaded, status: 'Complete!');
  }

  static Future<void> deleteModel() async {
    final dir = Directory(await getModelPath());
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

// ── Progress model ────────────────────────────────────────────────────────────

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
  // Phases: 'token' → user enters HF token | 'downloading' → progress bar
  String _phase = 'token';
  final TextEditingController _tokenCtrl = TextEditingController();
  bool _tokenObscured = true;

  DownloadProgress? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkSavedToken();
  }

  /// If a token was saved from a previous (interrupted) attempt, skip entry.
  Future<void> _checkSavedToken() async {
    final saved = await ModelDownloader.getSavedToken();
    if (saved != null && mounted) {
      _tokenCtrl.text = saved;
      setState(() => _phase = 'downloading');
      _startDownload(saved);
    }
  }

  Future<void> _onTokenSubmit() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) return;
    setState(() { _phase = 'downloading'; _error = null; });
    _startDownload(token);
  }

  Future<void> _startDownload(String token) async {
    setState(() => _error = null);
    try {
      await for (final p in ModelDownloader.downloadModel(token)) {
        if (!mounted) return;
        setState(() => _progress = p);
        if (p.progress >= 1.0) {
          await Future.delayed(const Duration(milliseconds: 500));
          widget.onComplete();
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        // Go back to token entry so they can correct it
        if (_error!.contains('Token rejected') || _error!.contains('401') || _error!.contains('403')) {
          _phase = 'token';
        }
      });
    }
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: _phase == 'token' ? _buildTokenEntry() : _buildProgress(),
        ),
      ),
    );
  }

  // ── Token entry UI ───────────────────────────────────────────────────────

  Widget _buildTokenEntry() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.psychology_rounded, size: 48, color: Colors.blue),
        ),
        const SizedBox(height: 32),
        const Text('Set Up Vision AI',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            textAlign: TextAlign.center),
        const SizedBox(height: 12),
        const Text(
          'Gemma 2B requires a free Hugging Face token.\n'
          'The token is only used to download the model — it\'s stored on this device only.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 32),

        // Steps
        _step('1', 'Go to  huggingface.co/google/gemma-2b-it-tflite'),
        _step('2', 'Log in and accept the Gemma licence'),
        _step('3', 'Go to  huggingface.co/settings/tokens  and create a Read token'),
        _step('4', 'Paste it below'),
        const SizedBox(height: 24),

        // Token field
        TextField(
          controller: _tokenCtrl,
          obscureText: _tokenObscured,
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
          decoration: InputDecoration(
            labelText: 'Hugging Face token  (hf_…)',
            labelStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            suffixIcon: IconButton(
              icon: Icon(_tokenObscured ? Icons.visibility : Icons.visibility_off,
                  color: Colors.white54),
              onPressed: () => setState(() => _tokenObscured = !_tokenObscured),
            ),
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
                textAlign: TextAlign.center),
          ),
        ],

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _onTokenSubmit,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Download Gemma 2B  (~1.5 GB)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'WiFi recommended · One-time download · Works fully offline after this.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white24, fontSize: 12, height: 1.5),
        ),
      ],
    );
  }

  Widget _step(String num, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24, height: 24,
            decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
            child: Center(child: Text(num,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5))),
        ],
      ),
    );
  }

  // ── Download progress UI ─────────────────────────────────────────────────

  Widget _buildProgress() {
    final pct = ((_progress?.progress ?? 0) * 100).toInt();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.psychology_rounded, size: 48, color: Colors.blue),
        ),
        const SizedBox(height: 32),
        const Text('Downloading Gemma 2B',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            textAlign: TextAlign.center),
        const SizedBox(height: 12),
        const Text(
          'Fetching from Hugging Face. Keep the app open.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 14),
        ),
        const SizedBox(height: 48),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$pct%', style: const TextStyle(color: Colors.white70, fontSize: 14)),
            Text(
              '${_progress?.downloadedMB ?? "0 MB"} / ${_progress?.totalMB ?? "~1500 MB"}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(_progress?.status ?? 'Preparing…',
            style: const TextStyle(color: Colors.white38, fontSize: 12)),

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
                onPressed: () => setState(() { _phase = 'token'; _error = null; }),
                icon: const Icon(Icons.refresh),
                label: const Text('Re-enter Token'),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 48),
        const Text(
          'One-time download · ~1.5 GB · WiFi recommended\nWorks fully offline after this.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white24, fontSize: 12, height: 1.6),
        ),
      ],
    );
  }
}
