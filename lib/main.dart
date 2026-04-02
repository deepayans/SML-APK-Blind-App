import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/model_downloader.dart';
import 'services/gemma_service.dart';
import 'services/tts_service.dart';
import 'services/stt_service.dart';
import 'providers/assistant_provider.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const VisionAssistantApp());
}

class VisionAssistantApp extends StatelessWidget {
  const VisionAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<GemmaService>(create: (_) => GemmaService()),
        Provider<TtsService>(create: (_) => TtsService()),
        Provider<SttService>(create: (_) => SttService()),
        ChangeNotifierProxyProvider3<GemmaService, TtsService, SttService,
            AssistantProvider>(
          create: (ctx) => AssistantProvider(
            gemmaService: ctx.read<GemmaService>(),
            ttsService: ctx.read<TtsService>(),
            sttService: ctx.read<SttService>(),
          ),
          update: (ctx, g, t, s, prev) => prev ??
              AssistantProvider(
                gemmaService: g,
                ttsService: t,
                sttService: s,
              ),
        ),
      ],
      child: MaterialApp(
        title: 'Vision Assistant',
        theme: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Colors.blue),
        ),
        debugShowCheckedModeBanner: false,
        home: const AppStartup(),
      ),
    );
  }
}

class AppStartup extends StatefulWidget {
  const AppStartup({super.key});

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  @override
  void initState() {
    super.initState();
    // ML Kit works immediately — go straight to the home screen.
    // The optional Gemma download is offered from Settings.
    WidgetsBinding.instance.addPostFrameCallback((_) => _goHome());
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF121212),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
