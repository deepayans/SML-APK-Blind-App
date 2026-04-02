import 'package:flutter/material.dart';
import '../services/tts_service.dart';
import '../services/preferences_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TtsService _tts = TtsService();
  final PreferencesService _prefs = PreferencesService();

  double _speechRate = 0.45;
  double _speechVolume = 1.0;
  bool _autoSpeak = true;
  bool _hapticEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _prefs.init();
    await _tts.initialize();
    setState(() {
      _speechRate = _prefs.speechRate;
      _speechVolume = _prefs.speechVolume;
      _autoSpeak = _prefs.autoSpeak;
      _hapticEnabled = _prefs.hapticEnabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text("Speech",
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Speech Rate", style: TextStyle(fontSize: 16)),
                  Slider(
                    value: _speechRate,
                    min: 0.1,
                    max: 1.0,
                    divisions: 9,
                    label: _speechRate.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() => _speechRate = value);
                      _prefs.speechRate = value;
                      _tts.setSpeechRate(value);
                    },
                  ),
                  const Text("Volume", style: TextStyle(fontSize: 16)),
                  Slider(
                    value: _speechVolume,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    label: _speechVolume.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() => _speechVolume = value);
                      _prefs.speechVolume = value;
                      _tts.setVolume(value);
                    },
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _tts.speak(
                        "This is how the speech sounds at the current settings."),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text("Test Speech"),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text("Behaviour",
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              title: const Text("Auto-speak Results"),
              subtitle: const Text("Automatically read descriptions"),
              value: _autoSpeak,
              onChanged: (value) {
                setState(() => _autoSpeak = value);
                _prefs.autoSpeak = value;
              },
            ),
          ),
          Card(
            child: SwitchListTile(
              title: const Text("Haptic Feedback"),
              subtitle: const Text("Vibrate on actions"),
              value: _hapticEnabled,
              onChanged: (value) {
                setState(() => _hapticEnabled = value);
                _prefs.hapticEnabled = value;
              },
            ),
          ),
          const SizedBox(height: 24),
          const Text("AI Model",
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.smart_toy_outlined),
                    title: Text("Gemma 2B IT CPU INT4 (optional)"),
                    subtitle: Text("On-device language model for richer descriptions"),
                  ),
                  Divider(),
                  Text(
                    "Without Gemma the app works using ML Kit alone — "
                    "objects and text are detected and spoken directly.\n\n"
                    "To enable Gemma for natural language descriptions:\n"
                    "1. Accept the licence at kaggle.com/models/google/gemma/tfLite\n"
                    "2. Download  gemma-2b-it-cpu-int4.bin  (~1.5 GB)\n"
                    "3. Copy the file to your phone and place it at:\n"
                    "   /sdcard/Download/gemma-mediapipe/gemma-2b-it-cpu-int4.bin\n\n"
                    "The app detects the file automatically on next launch.",
                    style: TextStyle(fontSize: 13, height: 1.5, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text("About",
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
          const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text("Version"),
              subtitle: Text("1.0.0")),
          const ListTile(
              leading: Icon(Icons.smart_toy_outlined),
              title: Text("AI Model"),
              subtitle: Text("Gemma 2B IT CPU INT4 (on-device)")),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }
}
