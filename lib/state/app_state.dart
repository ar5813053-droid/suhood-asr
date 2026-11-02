import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/asr/asr_engine.dart';
import '../engine/asr/model_manager.dart';
import '../engine/asr/sherpa_quran_asr.dart';
import '../engine/audio/audio_source.dart';
import '../engine/audio/mic_audio_source.dart';
import '../engine/audio/speech_gate.dart';
import '../engine/matcher/ayah_matcher.dart';
import '../engine/qiraat/qiraat.dart';
import '../engine/quran/quran_text.dart';

/// Application state for Milestone 2.1: gated mic + offline Quran ASR.
///
/// Critical rule: silence / ambient noise must NEVER produce a Quran transcript.
class AppState extends ChangeNotifier {
  final MicAudioSource micSource = MicAudioSource();
  final ModelManager modelManager = ModelManager();
  late final SherpaQuranAsrEngine asrEngine =
      SherpaQuranAsrEngine(modelManager: modelManager);
  final QuranTextProvider quranProvider = StubQuranTextProvider();
  final AyahMatcher matcher = StubAyahMatcher();
  final QiraatSelector qiraatSelector = StubQiraatSelector();
  final SpeechGate speechGate = SpeechGate();

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
  bool _debugMode = false;

  // Debug metrics
  int _asrCalls = 0;
  int _asrRejected = 0;
  int _lastInferenceMs = 0;
  String _lastRawAsr = '';
  String _vadStateLabel = 'silence';

  StreamSubscription<AudioChunk>? _audioSub;
  final List<int> _pcmBuffer = [];
  Timer? _segmentTimer;
  bool _processing = false;

  // Published sample index tracking to avoid re-decoding the same region

  bool get isRecording => _isRecording;
  bool get isDownloading => _isDownloading;
  String get liveTranscript => _liveTranscript;
  String get finalTranscript => _finalTranscript;
  String get transcriptDisplay {
    if (_finalTranscript.isEmpty && _liveTranscript.isEmpty) return '';
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
  bool get debugMode => _debugMode;
  int get asrCalls => _asrCalls;
  int get asrRejected => _asrRejected;
  int get lastInferenceMs => _lastInferenceMs;
  String get lastRawAsr => _lastRawAsr;
  String get vadStateLabel => _vadStateLabel;
  double get noiseFloor => speechGate.noiseFloor;

  void setDebugMode(bool v) {
    _debugMode = v;
    notifyListeners();
  }

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
    speechGate.reset();
    _isRecording = true;
    _audioLevel = 0.0;
    _vadStateLabel = 'silence';
    notifyListeners();

    final stream = micSource.start(const AudioCaptureConfig(sampleRate: 16000));
    _audioSub = stream.listen(
      (chunk) {
        if (!_isRecording) return;
        speechGate.processSamples(chunk.samples);
        _vadStateLabel = speechGate.state.name;
        _pcmBuffer.addAll(chunk.samples);
        _audioLevel = micSource.level;
        notifyListeners();
      },
      onError: (Object e) {
        _errorMessage = e.toString();
        stopRecording();
      },
    );

    // Check every 1.5 s — only ASR when SpeechGate accepts the segment.
    _segmentTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _processSegment(finalFlush: false);
    });
  }

  Future<void> _processSegment({required bool finalFlush}) async {
    if (_processing) return;
    if (_pcmBuffer.isEmpty) return;

    // Need enough audio to evaluate
    if (!finalFlush && _pcmBuffer.length < 8000) return;

    _processing = true;
    try {
      final take = finalFlush
          ? _pcmBuffer.length
          : (_pcmBuffer.length > 48000 ? 48000 : _pcmBuffer.length);
      if (take < 1600) return;

      final segment = List<int>.from(_pcmBuffer.sublist(0, take));

      // --- Speech gate: never ASR pure silence / ambient noise ---
      if (!speechGate.shouldRecognizeSegment(segment, finalFlush: finalFlush)) {
        _asrRejected++;
        // Drop most of the silent buffer; keep a short tail for continuity
        final keep = finalFlush ? 0 : 3200;
        if (_pcmBuffer.length > keep) {
          final start = _pcmBuffer.length - keep;
          final tail = _pcmBuffer.sublist(start);
          _pcmBuffer
            ..clear()
            ..addAll(tail);
        } else if (finalFlush) {
          _pcmBuffer.clear();
        }
        notifyListeners();
        return;
      }

      // Controlled overlap only for accepted speech segments (~0.4 s)
      final overlap = finalFlush ? 0 : 6400;
      final keepFrom = (take - overlap).clamp(0, _pcmBuffer.length);
      final remaining = _pcmBuffer.sublist(keepFrom);
      _pcmBuffer
        ..clear()
        ..addAll(remaining);

      final sw = Stopwatch()..start();
      _asrCalls++;
      final result = await asrEngine.recognize(
        AudioChunk(samples: segment, sampleRate: 16000),
      );
      sw.stop();
      _lastInferenceMs = sw.elapsedMilliseconds;
      _updateModelStatusLabel();

      if (result.errorMessage != null && result.hypotheses.isEmpty) {
        // Rejected by engine safeguards — do not surface as transcript
        _asrRejected++;
        _lastRawAsr = result.errorMessage ?? '';
        notifyListeners();
        return;
      }

      final text = result.bestText;
      _lastRawAsr = text;
      if (text.isEmpty) {
        _asrRejected++;
        notifyListeners();
        return;
      }

      _appendTranscript(text);
      notifyListeners();
    } finally {
      _processing = false;
    }
  }

  void _appendTranscript(String text) {
    final incoming = text.trim();
    if (incoming.isEmpty) return;

    if (_finalTranscript.isEmpty) {
      _finalTranscript = incoming;
      _liveTranscript = '';
      return;
    }

    // Deduplicate overlap at word boundary
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

    // Flush only if speech was present
    await _processSegment(finalFlush: true);

    _pcmBuffer.clear();
    _isRecording = false;
    _audioLevel = 0.0;
    _vadStateLabel = 'silence';
    _updateModelStatusLabel();
    notifyListeners();
  }

  void clearTranscript() {
    _liveTranscript = '';
    _finalTranscript = '';
    _detectedSurahAyah = '—';
    _errorMessage = null;
    _lastRawAsr = '';
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
    micSource.dispose();
    asrEngine.dispose();
    quranProvider.dispose();
    matcher.dispose();
    qiraatSelector.dispose();
    super.dispose();
  }
}
