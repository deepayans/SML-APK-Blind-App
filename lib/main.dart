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
                  gemmaService: g, ttsService: t, sttService: s),
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

/// Checks whether Gemma 2B has been downloaded.
/// • First launch → shows mandatory download screen (~1.5 GB, WiFi recommended)
/// • Subsequent launches → goes straight to the camera screen
class AppStartup extends StatefulWidget {
  const AppStartup({super.key});

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  bool _checking = true;
  bool _needsDownload = false;

  @override
  void initState() {
    super.initState();
    _checkModel();
  }

  Future<void> _checkModel() async {
    final needs = await ModelDownloader.isModelDownloaded() == false;
    if (!mounted) return;
    setState(() {
      _checking = false;
      _needsDownload = needs;
    });
    if (!needs) _goHome();
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A1A),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_needsDownload) {
      return ModelDownloadScreen(onComplete: _goHome);
    }
    return const Scaffold(
      backgroundColor: Color(0xFF0A0A1A),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
