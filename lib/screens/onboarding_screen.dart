import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/tts_service.dart';
import '../services/preferences_service.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final TtsService _tts = TtsService();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _pages = [
    {
      "title": "Welcome to Vision Assistant",
      "description": "Your AI-powered companion for understanding the world around you.",
      "icon": Icons.visibility,
      "speech": "Welcome to Vision Assistant. I will help you understand your surroundings.",
    },
    {
      "title": "Point and Describe",
      "description": "Point your camera at anything and tap to get a description.",
      "icon": Icons.camera_alt,
      "speech": "Point your camera at anything and tap the screen. I will describe what I see.",
    },
    {
      "title": "Voice Commands",
      "description": "Long-press to speak commands like describe or read text.",
      "icon": Icons.mic,
      "speech": "You can use voice commands. Long-press and say describe, read text, or find obstacles.",
    },
    {
      "title": "Ready to Start",
      "description": "Tap Start to begin using Vision Assistant.",
      "icon": Icons.check_circle,
      "speech": "You are all set! Tap Start to begin.",
    },
  ];

  @override
  void initState() {
    super.initState();
    _initTTS();
  }

  Future<void> _initTTS() async {
    await _tts.initialize();
    _speakCurrentPage();
  }

  void _speakCurrentPage() => _tts.speak(_pages[_currentPage]["speech"] as String);

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _completeOnboarding();
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = PreferencesService();
    await prefs.init();
    prefs.isOnboardingComplete = true;

    if (mounted) {
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                  onPressed: _completeOnboarding,
                  child: const Text("Skip", style: TextStyle(fontSize: 18))),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                  HapticFeedback.lightImpact();
                  _speakCurrentPage();
                },
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(page["icon"] as IconData, size: 100, color: Colors.blue),
                        const SizedBox(height: 40),
                        Text(page["title"] as String,
                            style: const TextStyle(
                                fontSize: 28, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        Text(page["description"] as String,
                            style: const TextStyle(fontSize: 18, color: Colors.white70),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _currentPage ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _currentPage ? Colors.blue : Colors.grey,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _nextPage,
                    child: Text(
                        _currentPage == _pages.length - 1 ? "Start" : "Next",
                        style: const TextStyle(fontSize: 20)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tts.dispose();
    _pageController.dispose();
    super.dispose();
  }
}
