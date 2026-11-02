import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/asr/asr_engine.dart';
import '../engine/asr/engine_ids.dart';
import '../engine/asr/engine_registry.dart';
import '../engine/asr/model_manager.dart';
import '../engine/asr/output_validator.dart';
import '../engine/asr/sherpa_quran_asr.dart';
import '../engine/asr/transcript_merger.dart';
import '../engine/asr/zipformer32_model_store.dart';
import '../engine/asr/sherpa_zipformer_quran32.dart';
import '../engine/audio/audio_source.dart';
import '../engine/audio/mic_audio_source.dart';
import '../engine/audio/speech_gate.dart';
import '../engine/matcher/ayah_matcher.dart';
import '../engine/qiraat/qiraat.dart';
import '../engine/quran/quran_text.dart';

/// Milestone 2.2 app state: calibration, validated ASR, reliable merge.
class AppState extends ChangeNotifier {
  final MicAudioSource micSource = MicAudioSource();
  final ModelManager modelManager = ModelManager();
  late final SherpaQuranAsrEngine asrEngine =
      SherpaQuranAsrEngine(modelManager: modelManager);
  final QuranTextProvider quranProvider = StubQuranTextProvider();
  final AyahMatcher matcher = StubAyahMatcher();
  final QiraatSelector qiraatSelector = StubQiraatSelector();
  final SpeechGate speechGate = SpeechGate();
  final AsrOutputValidator validator = AsrOutputValidator();
  final TranscriptMerger merger = TranscriptMerger();
  final EngineRegistry engineRegistry = EngineRegistry();
  final Zipformer32ModelStore zipformerStore = Zipformer32ModelStore();
  late final SherpaZipformerQuran32Engine zipformerEngine =
      SherpaZipformerQuran32Engine(store: zipformerStore);
  bool _isInitializingZipformer = false;
  String? _zipformerInitMessage;

  bool _isRecording = false;
  bool _isImportingZipformer = false;
  bool _isDownloading = false;
  String _detectedSurahAyah = '—';
  String _modelStatusLabel = 'Model: checking…';
  String _listenStatus = 'Idle';
  String? _errorMessage;
  bool _offlineMode = true;
  double _audioLevel = 0.0;
  double _downloadProgress = 0.0;
  bool _debugMode = false;

  int _asrCalls = 0;
  int _asrRejected = 0;
  int _asrAccepted = 0;
  int _lastInferenceMs = 0;
  String _lastRawAsr = '';
  String _lastFilteredAsr = '';
  String _lastRejectReason = '';
  String _lastMergeNote = '';
  String _vadStateLabel = 'silence';
  double _peakLevel = 0.0;

  StreamSubscription<AudioChunk>? _audioSub;
  final List<int> _pcmBuffer = [];
  Timer? _segmentTimer;
  bool _processing = false;
  bool _stopRequested = false;

  bool get isRecording => _isRecording;
  bool get isDownloading => _isDownloading;
  String get finalTranscript => merger.text;
  String get transcriptDisplay => merger.text;
  String get detectedSurahAyah => _detectedSurahAyah;
  String get modelStatusLabel => _modelStatusLabel;
  String get listenStatus => _listenStatus;
  String? get errorMessage => _errorMessage;
  bool get offlineMode => _offlineMode;
  double get audioLevel => _audioLevel;
  double get downloadProgress => _downloadProgress;
  AsrModelStatus get asrStatus => asrEngine.status;
  bool get modelReady => asrEngine.status == AsrModelStatus.ready;
  bool get debugMode => _debugMode;
  bool get isImportingZipformer => _isImportingZipformer;
  bool get isInitializingZipformer => _isInitializingZipformer;
  String? get zipformerInitMessage => _zipformerInitMessage;
  int get zipformerLastInitMs => zipformerEngine.lastInitMs;
  String get selectedEngineId => engineRegistry.selectedId;
  String get activeEngineLabel => engineDisplayName(engineRegistry.selectedId);
  /// Zipformer is never inference-ready in M2.4-A.
  bool get zipformerInferenceReady => zipformerStore.isReadyForInference;
  int get asrCalls => _asrCalls;
  int get asrRejected => _asrRejected;
  int get asrAccepted => _asrAccepted;
  int get lastInferenceMs => _lastInferenceMs;
  String get lastRawAsr => _lastRawAsr;
  String get lastFilteredAsr => _lastFilteredAsr;
  String get lastRejectReason => _lastRejectReason;
  String get lastMergeNote => _lastMergeNote;
  String get vadStateLabel => _vadStateLabel;
  double get noiseFloor => speechGate.noiseFloor;
  double get peakLevel => _peakLevel;

  void setDebugMode(bool v) {
    _debugMode = v;
    notifyListeners();
  }

  Future<void> initialize() async {
    await engineRegistry.load();
    await zipformerStore.refreshFromDisk();
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

  Future<void> selectEngine(String id) async {
    if (_isRecording) {
      await stopRecording();
    }
    await engineRegistry.select(id);
    _updateModelStatusLabel();
    notifyListeners();
  }

  Future<void> importZipformerModel() async {
    if (_isImportingZipformer) return;
    _isImportingZipformer = true;
    notifyListeners();
    final ok = await zipformerStore.importViaSaf(
      onProgress: (p) {
        notifyListeners();
      },
    );
    _isImportingZipformer = false;
    if (!ok && zipformerStore.lastError != null) {
      _errorMessage = zipformerStore.lastError;
    }
    notifyListeners();
  }

  Future<void> clearZipformerModel() async {
    await zipformerEngine.dispose();
    zipformerStore.inferenceInitialized = false;
    await zipformerStore.clear();
    _zipformerInitMessage = null;
    _updateModelStatusLabel();
    notifyListeners();
  }

  /// M2.4-B: construct OnlineRecognizer from imported files.
  Future<void> loadZipformerEngine() async {
    if (_isInitializingZipformer) return;
    if (_isRecording) {
      await stopRecording();
    }
    // Never load diagnostic + zipformer together: dispose diagnostic if needed
    // (diagnostic stays constructed but we only init zipformer here)
    _isInitializingZipformer = true;
    _zipformerInitMessage = 'Loading OnlineRecognizer…';
    notifyListeners();

    final result = await zipformerEngine.initializeFromStore();
    zipformerStore.inferenceInitialized = result.success;
    _zipformerInitMessage = result.message;
    _isInitializingZipformer = false;
    if (!result.success) {
      _errorMessage = result.message;
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
        if (engineRegistry.isDiagnosticSelected) {
          _modelStatusLabel = 'Diagnostic ready (quran-asr-small)';
        } else {
          _modelStatusLabel =
              'Primary: Zipformer 3.2 (files only — init in 2.4-B)';
        }
        break;
      case AsrModelStatus.error:
        _modelStatusLabel = 'Model: error';
        break;
      case AsrModelStatus.inferring:
        _modelStatusLabel = 'Model: recognizing…';
        break;
    }
    if (engineRegistry.isPrimarySelected) {
      if (zipformerEngine.isInitialized) {
        _modelStatusLabel =
            'Zipformer 3.2: Ready (${zipformerEngine.lastInitMs} ms)';
      } else if (zipformerStore.filesVerified) {
        _modelStatusLabel =
            'Zipformer 3.2: files imported — tap Load engine';
      } else if (zipformerStore.state == Zipformer32InstallState.notInstalled) {
        _modelStatusLabel = 'Zipformer 3.2: not installed';
      } else if (zipformerStore.state == Zipformer32InstallState.error) {
        _modelStatusLabel = 'Zipformer 3.2: install error';
      }
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
    // Primary Zipformer has no inference in M2.4-A.
    if (engineRegistry.isPrimarySelected) {
      if (!zipformerEngine.isInitialized) {
        _errorMessage =
            'Zipformer 3.2 not Ready. Import files and tap Load engine in Settings.';
        notifyListeners();
        return;
      }
      _errorMessage =
          'Streaming recognition is Milestone 2.4-C. Engine is loaded; mic streaming not enabled yet.';
      notifyListeners();
      return;
    }
    if (!modelReady) {
      _errorMessage =
          'Diagnostic model not ready. Download quran-asr-small first.';
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
    _stopRequested = false;
    _pcmBuffer.clear();
    speechGate.reset();
    // Keep prior transcript unless user cleared — do not wipe on restart
    _isRecording = true;
    _audioLevel = 0.0;
    _peakLevel = 0.0;
    _listenStatus = 'Calibrating noise…';
    _vadStateLabel = 'calibrating';
    notifyListeners();

    final stream = micSource.start(const AudioCaptureConfig(sampleRate: 16000));
    _audioSub = stream.listen(
      (chunk) {
        if (!_isRecording || _stopRequested) return;
        speechGate.processSamples(chunk.samples);
        _vadStateLabel = speechGate.state.name;
        if (speechGate.isCalibrating) {
          _listenStatus = 'Calibrating noise…';
        } else if (speechGate.state == SpeechState.speech ||
            speechGate.state == SpeechState.hangover) {
          _listenStatus = 'Listening';
        } else {
          _listenStatus = 'Listening';
        }
        _pcmBuffer.addAll(chunk.samples);
        _audioLevel = micSource.level;
        // peak from this chunk
        var peak = 0.0;
        for (final s in chunk.samples) {
          final a = (s / 32768.0).abs();
          if (a > peak) peak = a;
        }
        _peakLevel = peak;
        notifyListeners();
      },
      onError: (Object e) {
        _errorMessage = e.toString();
        stopRecording();
      },
    );

    _segmentTimer =
        Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!_stopRequested) {
        _processSegment(finalFlush: false);
      }
    });
  }

  Future<void> _processSegment({required bool finalFlush}) async {
    if (_processing) return;
    if (_pcmBuffer.isEmpty) return;
    if (!finalFlush && _pcmBuffer.length < 8000) return;
    if (_stopRequested && !finalFlush) return;

    _processing = true;
    try {
      final take = finalFlush
          ? _pcmBuffer.length
          : (_pcmBuffer.length > 48000 ? 48000 : _pcmBuffer.length);
      if (take < 1600) return;

      final segment = List<int>.from(_pcmBuffer.sublist(0, take));

      if (!speechGate.shouldRecognizeSegment(segment, finalFlush: finalFlush)) {
        _asrRejected++;
        _lastRejectReason = speechGate.isCalibrating
            ? 'calibration in progress'
            : 'speech gate: silence/noise';
        final keep = finalFlush ? 0 : 3200;
        if (_pcmBuffer.length > keep) {
          final tail = _pcmBuffer.sublist(_pcmBuffer.length - keep);
          _pcmBuffer
            ..clear()
            ..addAll(tail);
        } else if (finalFlush) {
          _pcmBuffer.clear();
        }
        notifyListeners();
        return;
      }

      final overlap = finalFlush ? 0 : 6400;
      final keepFrom = (take - overlap).clamp(0, _pcmBuffer.length);
      final remaining = _pcmBuffer.sublist(keepFrom);
      _pcmBuffer
        ..clear()
        ..addAll(remaining);

      if (_stopRequested && !finalFlush) return;

      final sw = Stopwatch()..start();
      _asrCalls++;
      final result = await asrEngine.recognize(
        AudioChunk(samples: segment, sampleRate: 16000),
      );
      sw.stop();
      _lastInferenceMs = sw.elapsedMilliseconds;
      _updateModelStatusLabel();

      if (_stopRequested && !finalFlush) return;

      final raw = result.bestText;
      _lastRawAsr = raw;

      if (result.errorMessage != null && raw.isEmpty) {
        _asrRejected++;
        _lastRejectReason = result.errorMessage!;
        notifyListeners();
        return;
      }

      final v = validator.validate(
        rawText: raw,
        sampleCount: segment.length,
        sampleRate: 16000,
      );
      _lastFilteredAsr = v.filteredText ?? '';
      _lastRejectReason = v.reason;

      if (v.decision == AsrValidationDecision.rejected) {
        _asrRejected++;
        notifyListeners();
        return;
      }

      // accepted or uncertain — publish (uncertain still shown; debug explains)
      final text = v.filteredText ?? raw;
      if (text.isEmpty) {
        _asrRejected++;
        notifyListeners();
        return;
      }

      final merge = merger.append(text);
      _lastMergeNote = merge.note;
      _asrAccepted++;
      notifyListeners();
    } finally {
      _processing = false;
    }
  }

  Future<void> stopRecording() async {
    _stopRequested = true;
    _segmentTimer?.cancel();
    _segmentTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    await micSource.stop();

    await _processSegment(finalFlush: true);

    _pcmBuffer.clear();
    _isRecording = false;
    _audioLevel = 0.0;
    _peakLevel = 0.0;
    _listenStatus = 'Idle';
    _vadStateLabel = 'silence';
    _updateModelStatusLabel();
    notifyListeners();
  }

  void clearTranscript() {
    merger.clear();
    _detectedSurahAyah = '—';
    _errorMessage = null;
    _lastRawAsr = '';
    _lastFilteredAsr = '';
    _lastRejectReason = '';
    _lastMergeNote = '';
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
    zipformerEngine.dispose();
    quranProvider.dispose();
    matcher.dispose();
    qiraatSelector.dispose();
    super.dispose();
  }
}
