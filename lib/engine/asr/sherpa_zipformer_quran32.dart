/// Zipformer Quran 3.2 — OnlineRecognizer + live streaming (M2.4-B/C).
///
/// Output is RAW phoneme/token text from the model, not verified Quran Arabic.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../audio/audio_source.dart';
import 'asr_engine.dart';
import 'zipformer32_model_store.dart';

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

/// One decode step result (partial or segment-final).
class ZipformerStreamUpdate {
  final String partialText;
  final List<String> tokens;
  final bool isEndpoint;
  final bool isSessionFinal;

  const ZipformerStreamUpdate({
    required this.partialText,
    required this.tokens,
    this.isEndpoint = false,
    this.isSessionFinal = false,
  });
}

/// PCM16 (int16 LE list) → float32 [-1, 1] for sherpa acceptWaveform.
Float32List pcm16ToFloat32(List<int> pcm16) {
  final out = Float32List(pcm16.length);
  for (var i = 0; i < pcm16.length; i++) {
    var s = pcm16[i];
    // Clamp to int16 range if values are already wide
    if (s > 32767) s = 32767;
    if (s < -32768) s = -32768;
    out[i] = s / 32768.0;
  }
  return out;
}

bool isPcmSilenceOrInvalid(List<int> pcm16) {
  if (pcm16.isEmpty) return true;
  var maxAbs = 0;
  for (final s in pcm16) {
    final a = s.abs();
    if (a > maxAbs) maxAbs = a;
  }
  return maxAbs < 8; // near-digital silence
}

class SherpaZipformerQuran32Engine implements AsrEngine {
  final Zipformer32ModelStore store;

  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  AsrModelStatus _status = AsrModelStatus.notPresent;
  String? _lastError;
  int lastInitMs = 0;
  bool _decodeBusy = false;
  bool _sessionActive = false;

  SherpaZipformerQuran32Engine({required this.store});

  @override
  String get name => 'SherpaZipformerQuran32 (online CTC)';

  @override
  AsrModelStatus get status => _status;

  @override
  String? get lastError => _lastError;

  bool get isInitialized =>
      _recognizer != null && _status == AsrModelStatus.ready;

  bool get isSessionActive => _sessionActive;

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
      final probe = recognizer.createStream();
      probe.free();

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

  /// Start one persistent OnlineStream for a recording session.
  void startSession() {
    if (!isInitialized) {
      throw StateError('Zipformer not initialized');
    }
    endSession(finalize: false);
    _stream = _recognizer!.createStream();
    _sessionActive = true;
    _decodeBusy = false;
  }

  /// Feed PCM16 samples continuously (including real silence) for timing/endpointing.
  /// Empty buffers are skipped. Near-zero PCM is still forwarded so the stream clock advances.
  ZipformerStreamUpdate? acceptPcm16(List<int> pcm16, {int sampleRate = 16000}) {
    if (!_sessionActive || _recognizer == null || _stream == null) {
      return null;
    }
    if (pcm16.isEmpty) return null;

    final floats = pcm16ToFloat32(pcm16);
    _stream!.acceptWaveform(samples: floats, sampleRate: sampleRate);

    if (_decodeBusy) {
      // Waveform was accepted; skip parallel decode.
      return null;
    }
    _decodeBusy = true;
    try {
      while (_recognizer!.isReady(_stream!)) {
        _recognizer!.decode(_stream!);
      }
      final result = _recognizer!.getResult(_stream!);
      final endpoint = _recognizer!.isEndpoint(_stream!);
      final text = result.text;
      final tokens = List<String>.from(result.tokens);
      if (endpoint) {
        // Finalize this segment's hypothesis, then reset stream state for the next.
        _recognizer!.reset(_stream!);
      }
      return ZipformerStreamUpdate(
        partialText: text,
        tokens: tokens,
        isEndpoint: endpoint,
      );
    } finally {
      _decodeBusy = false;
    }
  }

  /// End session: inputFinished + final decode.
  ZipformerStreamUpdate? endSession({bool finalize = true}) {
    final recognizer = _recognizer;
    final stream = _stream;
    _sessionActive = false;

    ZipformerStreamUpdate? finalUpdate;
    if (finalize && recognizer != null && stream != null) {
      try {
        stream.inputFinished();
        while (recognizer.isReady(stream)) {
          recognizer.decode(stream);
        }
        final result = recognizer.getResult(stream);
        finalUpdate = ZipformerStreamUpdate(
          partialText: result.text,
          tokens: List<String>.from(result.tokens),
          isEndpoint: true,
          isSessionFinal: true,
        );
      } catch (_) {}
    }

    try {
      stream?.free();
    } catch (_) {}
    _stream = null;
    _decodeBusy = false;
    return finalUpdate;
  }

  @override
  Future<AsrResult> recognize(AudioChunk chunk) async {
    // One-shot not preferred for streaming engine; used only if needed.
    if (!isInitialized) {
      return AsrResult(
        hypotheses: const [],
        isFinal: true,
        status: _status,
        errorMessage: _lastError ?? 'Zipformer 3.2 not initialized',
      );
    }
    startSession();
    final u = acceptPcm16(chunk.samples, sampleRate: chunk.sampleRate);
    final fin = endSession(finalize: true);
    final text = fin?.partialText ?? u?.partialText ?? '';
    return AsrResult(
      hypotheses: text.isEmpty
          ? const []
          : [AsrHypothesis(text: text, confidence: 0.5)],
      isFinal: true,
      status: _status,
    );
  }

  @override
  Stream<AsrResult> recognizeStream(Stream<AudioChunk> audioStream) {
    return Stream.error(
      StateError('Use acceptPcm16 session API for Zipformer streaming'),
    );
  }

  @override
  Future<void> dispose() async {
    endSession(finalize: false);
    try {
      _recognizer?.free();
    } catch (_) {}
    _recognizer = null;
    _status = AsrModelStatus.notPresent;
  }
}
