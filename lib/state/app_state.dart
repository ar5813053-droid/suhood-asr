import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/asr/asr_engine.dart';
import '../engine/asr/model_manager.dart';
import '../engine/asr/sherpa_quran_asr.dart';
import '../engine/audio/audio_source.dart';
import '../engine/audio/mic_audio_source.dart';
import '../engine/matcher/ayah_matcher.dart';
import '../engine/qiraat/qiraat.dart';
import '../engine/quran/quran_text.dart';

/// Application state for Milestone 2: real mic + real Quran ASR.
class AppState extends ChangeNotifier {
  final MicAudioSource micSource = MicAudioSource();
  final ModelManager modelManager = ModelManager();
  late final SherpaQuranAsrEngine asrEngine =
      SherpaQuranAsrEngine(modelManager: modelManager);
  final QuranTextProvider quranProvider = StubQuranTextProvider();
  final AyahMatcher matcher = StubAyahMatcher();
  final QiraatSelector qiraatSelector = StubQiraatSelector();

  bool _isRecording = false;
  bool _isDownloading = false;
  String _liveTranscript = '';
  String _finalTranscript = '';
  String _detectedSurahAyah = '—';
  String _modelStatusLabel = 'Model: checking…';
  String? _errorMessage;
  bool _offlineMode = true;
  double _audioLevel = 0.0;
  double _downloadProgress = 0.0;

  StreamSubscription<AudioChunk>? _audioSub;
  StreamSubscription<AsrResult>? _asrSub;
  final List<int> _pcmBuffer = [];
  Timer? _segmentTimer;

  bool get isRecording => _isRecording;
  bool get isDownloading => _isDownloading;
  String get liveTranscript => _liveTranscript;
  String get finalTranscript => _finalTranscript;
  String get transcriptDisplay {
    if (_finalTranscript.isEmpty && _liveTranscript.isEmpty) {
      return '';
    }
    if (_liveTranscript.isEmpty) return _finalTranscript;
    if (_finalTranscript.isEmpty) return _liveTranscript;
    return '$_finalTranscript $_liveTranscript'.trim();
  }

  String get detectedSurahAyah => _detectedSurahAyah;
  String get modelStatusLabel => _modelStatusLabel;
  String? get errorMessage => _errorMessage;
  bool get offlineMode => _offlineMode;
  double get audioLevel => _audioLevel;
  double get downloadProgress => _downloadProgress;
  AsrModelStatus get asrStatus => asrEngine.status;
  bool get modelReady => asrEngine.status == AsrModelStatus.ready;

  Future<void> initialize() async {
    await quranProvider.initialize();
    await matcher.initialize(quranProvider, const MatcherConfig());

    final ready = await modelManager.isReady();
    if (ready) {
      await asrEngine.initialize(const AsrConfig());
    } else {
      _modelStatusLabel = 'Model: not downloaded';
    }
    _updateModelStatusLabel();
    notifyListeners();
  }

  void _updateModelStatusLabel() {
    switch (asrEngine.status) {
      case AsrModelStatus.notPresent:
        _modelStatusLabel = modelManager.state == ModelDownloadState.missing
            ? 'Model: not downloaded'
            : 'Model: not loaded';
        break;
      case AsrModelStatus.loading:
        _modelStatusLabel = _isDownloading
            ? 'Model: downloading ${(downloadProgress * 100).toStringAsFixed(0)}%'
            : 'Model: loading…';
        break;
      case AsrModelStatus.ready:
        _modelStatusLabel = 'Model: ready (quran-asr-small)';
        break;
      case AsrModelStatus.error:
        _modelStatusLabel = 'Model: error';
        break;
      case AsrModelStatus.inferring:
        _modelStatusLabel = 'Model: recognizing…';
        break;
    }
  }

  Future<void> downloadAndLoadModel() async {
    if (_isDownloading) return;
    _isDownloading = true;
    _errorMessage = null;
    _downloadProgress = 0.0;
    _updateModelStatusLabel();
    notifyListeners();

    final ok = await asrEngine.ensureModelAndLoad(
      onProgress: (p) {
        _downloadProgress = p;
        _updateModelStatusLabel();
        notifyListeners();
      },
    );

    _isDownloading = false;
    if (!ok) {
      _errorMessage = asrEngine.lastError ?? 'Download failed';
    }
    _updateModelStatusLabel();
    notifyListeners();
  }

  Future<void> toggleRecording() async {
    if (_isRecording) {
      await stopRecording();
    } else {
      await startRecording();
    }
  }

  Future<void> startRecording() async {
    if (_isRecording) return;

    if (!modelReady) {
      _errorMessage =
          'Model not ready. Tap "Download model" first (≈36 MB, one-time).';
      notifyListeners();
      return;
    }

    final permitted = await micSource.requestPermission();
    if (!permitted) {
      _errorMessage = 'Microphone permission denied';
      notifyListeners();
      return;
    }

    _errorMessage = null;
    _liveTranscript = '';
    _pcmBuffer.clear();
    _isRecording = true;
    _audioLevel = 0.0;
    notifyListeners();

    final stream = micSource.start(const AudioCaptureConfig(sampleRate: 16000));
    _audioSub = stream.listen(
      (chunk) {
        _pcmBuffer.addAll(chunk.samples);
        _audioLevel = micSource.level;
        notifyListeners();
      },
      onError: (Object e) {
        _errorMessage = e.toString();
        stopRecording();
      },
    );

    _segmentTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _processSegment(finalFlush: false);
    });
  }

  Future<void> _processSegment({required bool finalFlush}) async {
    if (_pcmBuffer.isEmpty) return;
    if (!finalFlush && _pcmBuffer.length < 6400) return;

    final take = finalFlush
        ? _pcmBuffer.length
        : (_pcmBuffer.length > 48000 ? 48000 : _pcmBuffer.length);
    if (take < 1600) return;

    final segment = _pcmBuffer.sublist(0, take);
    final keepFrom = (take - 8000).clamp(0, _pcmBuffer.length);
    final remaining = _pcmBuffer.sublist(keepFrom);
    _pcmBuffer
      ..clear()
      ..addAll(remaining);

    final result = await asrEngine.recognize(
      AudioChunk(samples: segment, sampleRate: 16000),
    );
    _updateModelStatusLabel();

    if (result.errorMessage != null && result.hypotheses.isEmpty) {
      _errorMessage = result.errorMessage;
      notifyListeners();
      return;
    }

    final text = result.bestText;
    if (text.isEmpty) {
      notifyListeners();
      return;
    }

    _appendTranscript(text);
    notifyListeners();
  }

  void _appendTranscript(String text) {
    final incoming = text.trim();
    if (incoming.isEmpty) return;

    if (_finalTranscript.isEmpty) {
      _finalTranscript = incoming;
      _liveTranscript = '';
      return;
    }

    final existing = _finalTranscript.split(RegExp(r'\s+'));
    final next = incoming.split(RegExp(r'\s+'));
    var overlap = 0;
    final maxCheck =
        existing.length < next.length ? existing.length : next.length;
    for (var k = maxCheck; k > 0; k--) {
      final tail = existing.sublist(existing.length - k).join(' ');
      final head = next.sublist(0, k).join(' ');
      if (tail == head) {
        overlap = k;
        break;
      }
    }
    final novel = next.sublist(overlap).join(' ').trim();
    if (novel.isNotEmpty) {
      _finalTranscript = '$_finalTranscript $novel'.trim();
    }
    _liveTranscript = '';
  }

  Future<void> stopRecording() async {
    _segmentTimer?.cancel();
    _segmentTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    await micSource.stop();

    await _processSegment(finalFlush: true);

    _isRecording = false;
    _audioLevel = 0.0;
    _updateModelStatusLabel();
    notifyListeners();
  }

  void clearTranscript() {
    _liveTranscript = '';
    _finalTranscript = '';
    _detectedSurahAyah = '—';
    _errorMessage = null;
    notifyListeners();
  }

  void setOfflineMode(bool value) {
    _offlineMode = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _segmentTimer?.cancel();
    _audioSub?.cancel();
    _asrSub?.cancel();
    micSource.dispose();
    asrEngine.dispose();
    quranProvider.dispose();
    matcher.dispose();
    qiraatSelector.dispose();
    super.dispose();
  }
}
