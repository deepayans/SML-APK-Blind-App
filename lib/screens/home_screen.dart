import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';

import '../providers/assistant_provider.dart';
import '../models/assistant_mode.dart';
import '../theme/app_theme.dart';
import '../widgets/mode_selector.dart';
import '../widgets/status_display.dart';
import '../widgets/capture_button.dart';
import 'settings_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AssistantProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          body: GestureDetector(
            onTap: () {
              if (provider.isReady && !provider.isProcessing) {
                provider.captureAndAnalyze();
              }
            },
            onDoubleTap: () => provider.cycleMode(),
            onLongPress: () {
              if (!provider.isListening) provider.startListening();
            },
            onLongPressEnd: (_) {
              if (provider.isListening) provider.stopListening();
            },
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null) {
                if (details.primaryVelocity! > 0) {
                  final modes = AssistantMode.values;
                  final currentIndex = modes.indexOf(provider.mode);
                  final prevIndex = (currentIndex - 1 + modes.length) % modes.length;
                  provider.setMode(modes[prevIndex]);
                } else {
                  provider.cycleMode();
                }
              }
            },
            child: Stack(
              children: [
                if (provider.isCameraInitialized)
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.2,
                      child: CameraPreview(provider.cameraController),
                    ),
                  ),
                SafeArea(
                  child: Column(
                    children: [
                      _buildTopBar(context, provider),
                      ModeSelector(
                        currentMode: provider.mode,
                        onModeChanged: provider.setMode,
                      ),
                      Expanded(
                        child: StatusDisplay(
                          statusMessage: provider.statusMessage,
                          isProcessing: provider.isProcessing,
                          isListening: provider.isListening,
                          lastResult: provider.lastResult,
                        ),
                      ),
                      _buildInstructions(context),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: CaptureButton(
                      isProcessing: provider.isProcessing,
                      isListening: provider.isListening,
                      onPressed: provider.captureAndAnalyze,
                      onLongPress: provider.startListening,
                    ),
                  ),
                ),
                if (provider.isListening) _buildListeningOverlay(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context, AssistantProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.history, size: 32),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          const Text("Vision Assistant",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.settings, size: 32),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Text(
        "TAP: Describe  •  DOUBLE-TAP: Mode  •  HOLD: Voice\nSWIPE: Change mode",
        style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.7)),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildListeningOverlay(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                  color: AppTheme.primaryColor, shape: BoxShape.circle),
              child: const Icon(Icons.mic, size: 60, color: Colors.white),
            ),
            const SizedBox(height: 24),
            const Text("Listening...",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("Say a command",
                style: TextStyle(fontSize: 18, color: Colors.white.withOpacity(0.8))),
          ],
        ),
      ),
    );
  }
}
