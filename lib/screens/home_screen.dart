import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/assistant_mode.dart';
import '../providers/assistant_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _isInitializing = true;
  String _initError = '';

  @override
  void initState() {
    super.initState();
    _initializeAll();
  }

  Future<void> _initializeAll() async {
    await _requestPermissions();
    await _initializeCamera();

    if (mounted) {
      // initialize() loads Gemma — must succeed, no silent fallback
      await context.read<AssistantProvider>().initialize();
      setState(() => _isInitializing = false);
    }
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera, Permission.microphone].request();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(back, ResolutionPreset.medium, enableAudio: false);
      await _cameraController!.initialize();
      if (mounted) setState(() => _isCameraReady = true);
    } catch (e) {
      setState(() => _initError = 'Camera error: $e');
    }
  }

  Future<void> _captureAndAnalyze() async {
    if (!_isCameraReady || _cameraController == null) return;
    final provider = context.read<AssistantProvider>();
    if (provider.isProcessing) return;
    try {
      final image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();
      await provider.analyzeImage(bytes);
    } catch (e) {
      debugPrint('Capture error: $e');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<AssistantProvider>(
        builder: (context, provider, child) {

          // ── Initializing ──────────────────────────────────────────────
          if (_isInitializing) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.blue),
                  const SizedBox(height: 20),
                  Text(
                    provider.statusMessage,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // ── Init error ────────────────────────────────────────────────
          if (_initError.isNotEmpty || !provider.isModelLoaded) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 64),
                    const SizedBox(height: 20),
                    Text(
                      _initError.isNotEmpty
                          ? _initError
                          : provider.statusMessage,
                      style: const TextStyle(color: Colors.red, fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() { _isInitializing = true; _initError = ''; });
                        _initializeAll();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          // ── Main camera screen ────────────────────────────────────────
          return Stack(
            children: [

              // Camera preview
              if (_isCameraReady && _cameraController != null)
                Positioned.fill(child: CameraPreview(_cameraController!))
              else
                const Positioned.fill(
                  child: ColoredBox(color: Colors.black,
                    child: Center(child: Icon(Icons.camera_alt, size: 64, color: Colors.white24))),
                ),

              // Tap / double-tap / long-press handler
              Positioned.fill(
                child: GestureDetector(
                  onTap: _captureAndAnalyze,
                  onDoubleTap: provider.repeatLastResponse,
                  onLongPress: provider.startVoiceCommand,
                  child: Container(color: Colors.transparent),
                ),
              ),

              // ── Top status bar ──────────────────────────────────────
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 16, right: 16, bottom: 8,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Vision Assistant',
                          style: TextStyle(color: Colors.white, fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: provider.isProcessing ? Colors.orange : Colors.green,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          provider.isProcessing ? 'Analyzing…' : 'Ready',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Bottom controls ─────────────────────────────────────
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 16,
                    top: 16, left: 16, right: 16,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter, end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: AssistantMode.values.map((mode) {
                            final isSelected = provider.currentMode == mode;
                            final name = mode.name[0].toUpperCase() + mode.name.substring(1);
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceChip(
                                label: Text(name),
                                selected: isSelected,
                                onSelected: (_) => provider.setMode(mode),
                                selectedColor: Colors.blue,
                                backgroundColor: Colors.grey[800],
                                labelStyle: TextStyle(
                                    color: isSelected ? Colors.white : Colors.white70),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text('Tap: Analyze  |  Double-tap: Repeat  |  Hold: Voice',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
              ),

              // ── Processing overlay ──────────────────────────────────
              if (provider.isProcessing)
                Positioned.fill(
                  child: Container(
                    color: Colors.black45,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.blue),
                          SizedBox(height: 16),
                          Text('Analyzing…',
                              style: TextStyle(color: Colors.white, fontSize: 18)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
