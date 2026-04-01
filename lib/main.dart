import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';

import 'providers/assistant_provider.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/preferences_service.dart';
import 'theme/app_theme.dart';

late List<CameraDescription> cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  cameras = await availableCameras();

  final prefs = PreferencesService();
  await prefs.init();
  final onboardingComplete = prefs.isOnboardingComplete;

  runApp(VisionAssistantApp(
    showOnboarding: !onboardingComplete,
  ));
}

class VisionAssistantApp extends StatelessWidget {
  final bool showOnboarding;

  const VisionAssistantApp({
    super.key,
    this.showOnboarding = false,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AssistantProvider(cameras: cameras),
        ),
      ],
      child: MaterialApp(
        title: 'Vision Assistant',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: showOnboarding
            ? const OnboardingScreen()
            : const HomeScreen(),
      ),
    );
  }
}
