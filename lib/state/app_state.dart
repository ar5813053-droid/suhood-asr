import 'package:flutter/foundation.dart';

import '../engine/asr/asr_engine.dart';
import '../engine/audio/audio_source.dart';
import '../engine/matcher/ayah_matcher.dart';
import '../engine/qiraat/qiraat.dart';
import '../engine/quran/quran_text.dart';

/// Central application state for Milestone 1.
///
/// Only UI-level recording state and placeholders are implemented.
/// Real audio, ASR and matching are deliberately stubs.
class AppState extends ChangeNotifier {
  // --- Engines (stubs in M1) ---
  final AudioSource audioSource = StubAudioSource();
  final AsrEngine asrEngine = StubAsrEngine();
  final QuranTextProvider quranProvider = StubQuranTextProvider();
  final AyahMatcher matcher = StubAyahMatcher();
  final QiraatSelector qiraatSelector = StubQiraatSelector();

  // --- UI state ---
  bool _isRecording = false;
  String _liveTranscript = ''; // intentionally empty until real ASR
  String _detectedSurahAyah = '—';
  String _modelStatusLabel = 'Model: not loaded';
  bool _offlineMode = true;

  bool get isRecording => _isRecording;
  String get liveTranscript => _liveTranscript;
  String get detectedSurahAyah => _detectedSurahAyah;
  String get modelStatusLabel => _modelStatusLabel;
  bool get offlineMode => _offlineMode;
  AsrModelStatus get asrStatus => asrEngine.status;

  Future<void> initialize() async {
    await quranProvider.initialize();
    await asrEngine.initialize(const AsrConfig());
    await matcher.initialize(quranProvider, const MatcherConfig());
    _updateModelStatusLabel();
    notifyListeners();
  }

  void _updateModelStatusLabel() {
    switch (asrEngine.status) {
      case AsrModelStatus.notPresent:
        _modelStatusLabel = 'Model: not loaded (M1)';
        break;
      case AsrModelStatus.loading:
        _modelStatusLabel = 'Model: loading…';
        break;
      case AsrModelStatus.ready:
        _modelStatusLabel = 'Model: ready';
        break;
      case AsrModelStatus.error:
        _modelStatusLabel = 'Model: error';
        break;
      case AsrModelStatus.inferring:
        _modelStatusLabel = 'Model: listening…';
        break;
    }
  }

  /// Start/stop recording (UI + state only).
  /// Does not claim that speech recognition is happening.
  Future<void> toggleRecording() async {
    if (_isRecording) {
      await audioSource.stop();
      _isRecording = false;
      // Keep any previous transcript; do not invent new text.
    } else {
      // Clear previous placeholders so the user sees a clean slate.
      _liveTranscript = '';
      _detectedSurahAyah = '—';
      _isRecording = true;
      // Start the stub source; it emits nothing.
      audioSource.start(const AudioCaptureConfig());
    }
    _updateModelStatusLabel();
    notifyListeners();
  }

  void setOfflineMode(bool value) {
    _offlineMode = value;
    notifyListeners();
  }

  @override
  void dispose() {
    audioSource.dispose();
    asrEngine.dispose();
    quranProvider.dispose();
    matcher.dispose();
    qiraatSelector.dispose();
    super.dispose();
  }
}
