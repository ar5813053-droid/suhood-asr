/// Zipformer Quran 3.2 — OnlineRecognizer initialization (Milestone 2.4-B).
///
/// Loads sherpa-onnx OnlineZipformer2Ctc from validated local files.
/// Does NOT run microphone streaming (that is M2.4-C).
library;

import 'dart:async';
import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../audio/audio_source.dart';
import 'asr_engine.dart';
import 'zipformer32_model_store.dart';

/// Result of a load attempt.
class Zipformer32InitResult {
  final bool success;
  final String message;
  final int elapsedMs;
  final String? detail;

  const Zipformer32InitResult({
    required this.success,
    required this.message,
    required this.elapsedMs,
    this.detail,
  });
}

class SherpaZipformerQuran32Engine implements AsrEngine {
  final Zipformer32ModelStore store;

  sherpa.OnlineRecognizer? _recognizer;
  AsrModelStatus _status = AsrModelStatus.notPresent;
  String? _lastError;
  int lastInitMs = 0;

  SherpaZipformerQuran32Engine({required this.store});

  @override
  String get name => 'SherpaZipformerQuran32 (online CTC)';

  @override
  AsrModelStatus get status => _status;

  @override
  String? get lastError => _lastError;

  /// True only after OnlineRecognizer was constructed successfully.
  bool get isInitialized =>
      _recognizer != null && _status == AsrModelStatus.ready;

  /// Initialize OnlineRecognizer from store paths after validation.
  Future<Zipformer32InitResult> initializeFromStore() async {
    await dispose();
    _lastError = null;
    lastInitMs = 0;

    if (!store.filesVerified) {
      _status = AsrModelStatus.notPresent;
      _lastError = 'Model files not imported or not validated';
      return Zipformer32InitResult(
        success: false,
        message: _lastError!,
        elapsedMs: 0,
      );
    }

    final onnx = store.onnxPath;
    final tokens = store.tokensPath;
    if (onnx == null || tokens == null) {
      _status = AsrModelStatus.notPresent;
      _lastError = 'Missing onnx or tokens path';
      return Zipformer32InitResult(
        success: false,
        message: _lastError!,
        elapsedMs: 0,
      );
    }

    if (!await File(onnx).exists() || !await File(tokens).exists()) {
      _status = AsrModelStatus.notPresent;
      _lastError = 'Model files missing on disk';
      return Zipformer32InitResult(
        success: false,
        message: _lastError!,
        elapsedMs: 0,
      );
    }

    final o = await Zipformer32ModelStore.validateOnnxFile(File(onnx));
    final t = await Zipformer32ModelStore.validateTokensFile(File(tokens));
    if (!o.ok || !t.ok) {
      _status = AsrModelStatus.error;
      _lastError = [if (!o.ok) o.message, if (!t.ok) t.message].join('; ');
      return Zipformer32InitResult(
        success: false,
        message: _lastError!,
        elapsedMs: 0,
      );
    }

    _status = AsrModelStatus.loading;
    final sw = Stopwatch()..start();

    try {
      final zipformer2Ctc = sherpa.OnlineZipformer2CtcModelConfig(model: onnx);
      final modelConfig = sherpa.OnlineModelConfig(
        zipformer2Ctc: zipformer2Ctc,
        tokens: tokens,
        numThreads: 2,
        provider: 'cpu',
        debug: false,
        modelType: 'zipformer2',
      );
      final config = sherpa.OnlineRecognizerConfig(
        feat: const sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
        model: modelConfig,
        decodingMethod: 'greedy_search',
        enableEndpoint: true,
      );

      final recognizer = sherpa.OnlineRecognizer(config);
      // Ensure native side accepts the graph by allocating a stream.
      final stream = recognizer.createStream();
      stream.free();

      _recognizer = recognizer;
      sw.stop();
      lastInitMs = sw.elapsedMilliseconds;
      _status = AsrModelStatus.ready;
      _lastError = null;
      return Zipformer32InitResult(
        success: true,
        message: 'OnlineRecognizer ready (${lastInitMs} ms)',
        elapsedMs: lastInitMs,
      );
    } catch (e, st) {
      sw.stop();
      lastInitMs = sw.elapsedMilliseconds;
      _recognizer = null;
      _status = AsrModelStatus.error;
      _lastError = e.toString();
      return Zipformer32InitResult(
        success: false,
        message: 'Native init failed: $e',
        elapsedMs: lastInitMs,
        detail: st.toString(),
      );
    }
  }

  @override
  Future<void> initialize(AsrConfig config) async {
    await initializeFromStore();
  }

  /// Not used in M2.4-B — streaming inference is M2.4-C.
  @override
  Future<AsrResult> recognize(AudioChunk chunk) async {
    return AsrResult(
      hypotheses: const [],
      isFinal: true,
      status: _status,
      errorMessage: isInitialized
          ? 'Streaming inference not enabled (Milestone 2.4-C)'
          : (_lastError ?? 'Zipformer 3.2 not initialized'),
    );
  }

  @override
  Stream<AsrResult> recognizeStream(Stream<AudioChunk> audioStream) {
    return Stream.error(
      StateError('Streaming not implemented in M2.4-B'),
    );
  }

  @override
  Future<void> dispose() async {
    try {
      _recognizer?.free();
    } catch (_) {}
    _recognizer = null;
    _status = AsrModelStatus.notPresent;
  }
}
