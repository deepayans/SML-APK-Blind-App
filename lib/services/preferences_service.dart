import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static PreferencesService? _instance;
  late SharedPreferences _prefs;

  factory PreferencesService() {
    _instance ??= PreferencesService._internal();
    return _instance!;
  }

  PreferencesService._internal();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  bool get isOnboardingComplete => _prefs.getBool('onboarding_complete') ?? false;
  set isOnboardingComplete(bool value) => _prefs.setBool('onboarding_complete', value);

  double get speechRate => _prefs.getDouble('speech_rate') ?? 0.45;
  set speechRate(double value) => _prefs.setDouble('speech_rate', value);

  double get speechVolume => _prefs.getDouble('speech_volume') ?? 1.0;
  set speechVolume(double value) => _prefs.setDouble('speech_volume', value);

  bool get hapticEnabled => _prefs.getBool('haptic_enabled') ?? true;
  set hapticEnabled(bool value) => _prefs.setBool('haptic_enabled', value);

  bool get autoSpeak => _prefs.getBool('auto_speak') ?? true;
  set autoSpeak(bool value) => _prefs.setBool('auto_speak', value);
}
