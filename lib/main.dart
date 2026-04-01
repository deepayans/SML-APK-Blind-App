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
        ChangeNotifierProxyProvider3<GemmaService, TtsService, SttService, AssistantProvider>(
          create: (ctx) => AssistantProvider(
            gemmaService: ctx.read<GemmaService>(),
            ttsService: ctx.read<TtsService>(),
            sttService: ctx.read<SttService>(),
          ),
          update: (ctx, g, t, s, prev) => prev ?? AssistantProvider(
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
  bool _checking = true;
  bool _needsDownload = false;

  @override
  void initState() {
    super.initState();
    _checkModel();
  }

  Future<void> _checkModel() async {
    final needs = !(await ModelDownloader.isModelDownloaded());
    if (!mounted) return;
    if (needs) {
      setState(() {
        _checking = false;
        _needsDownload = true;
      });
    } else {
      _goHome();
    }
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_needsDownload) {
      return ModelDownloadScreen(onComplete: _goHome);
    }
    return const HomeScreen();
  }
}
