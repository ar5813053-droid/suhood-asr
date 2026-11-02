/// Offline Quran ASR using Abdou/quran-asr-small via sherpa_onnx.
///
/// The model is a Zipformer/Conformer CTC (int8 ONNX, ~36 MB).
/// Inference is offline (chunk / segment based), not true frame-streaming.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../audio/audio_source.dart';
import '../audio/speech_gate.dart';
import 'asr_engine.dart';
import 'model_manager.dart';

/// Converts PCM16 samples to float32 in [-1, 1] for sherpa-onnx.
Float32List pcm16ToFloat32(List<int> samples) {
  final out = Float32List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    out[i] = samples[i] / 32768.0;
  }
  return out;
}

/// Greedy CTC result text uses ▁ as word separator; normalize for display.
String normalizeTranscript(String raw) {
  return raw.replaceAll('▁', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

class SherpaQuranAsrEngine implements AsrEngine {
  final ModelManager modelManager;

  sherpa.OfflineRecognizer? _recognizer;
  AsrModelStatus _status = AsrModelStatus.notPresent;
  String? _lastError;

  SherpaQuranAsrEngine({ModelManager? modelManager})
      : modelManager = modelManager ?? ModelManager();

  @override
  String get name => 'SherpaQuranAsr (quran-asr-small)';

  @override
  AsrModelStatus get status => _status;

  @override
  String? get lastError => _lastError;

  @override
  Future<void> initialize(AsrConfig config) async {
    _lastError = null;

    final ready = await modelManager.isReady();
    if (!ready) {
      _status = AsrModelStatus.notPresent;
      return;
    }

    await _loadRecognizer();
  }

  /// Download model if needed, then load the recognizer.
  Future<bool> ensureModelAndLoad({
    void Function(double p)? onProgress,
  }) async {
    _status = AsrModelStatus.loading;
    _lastError = null;

    final ok = await modelManager.ensureDownloaded(onProgress: onProgress);
    if (!ok) {
      _status = AsrModelStatus.error;
      _lastError = modelManager.lastError ?? 'Model download failed';
      return false;
    }

    return _loadRecognizer();
  }

  Future<bool> _loadRecognizer() async {
    try {
      final modelPath = modelManager.modelPath;
      final tokensPath = modelManager.tokensPath;
      if (modelPath == null || tokensPath == null) {
        _status = AsrModelStatus.notPresent;
        return false;
      }

      // Zipformer CTC offline config (matches Python from_zipformer_ctc).
      final zipformerCtc = sherpa.OfflineZipformerCtcModelConfig(
        model: modelPath,
      );
      final modelConfig = sherpa.OfflineModelConfig(
        zipformerCtc: zipformerCtc,
        tokens: tokensPath,
        numThreads: 2,
        debug: false,
        modelType: '', // auto / zipformer-ctc path
      );
      final config = sherpa.OfflineRecognizerConfig(
        model: modelConfig,
      );

      _recognizer?.free();
      _recognizer = sherpa.OfflineRecognizer(config);
      _status = AsrModelStatus.ready;
      _lastError = null;
      return true;
    } catch (e) {
      _status = AsrModelStatus.error;
      _lastError = e.toString();
      _recognizer = null;
      return false;
    }
  }

  @override
  Future<AsrResult> recognize(AudioChunk chunk) async {
    if (_recognizer == null || _status != AsrModelStatus.ready) {
      return AsrResult(
        hypotheses: const [],
        isFinal: true,
        status: _status,
        errorMessage: _lastError ?? 'ASR model not ready',
      );
    }
    // Hard reject invalid / silent buffers before touching the model.
    if (!isValidPcmForAsr(chunk, minSamples: 1600)) {
      return const AsrResult(
        hypotheses: [],
        isFinal: true,
        status: AsrModelStatus.ready,
        errorMessage: 'rejected: invalid or silent PCM',
      );
    }

    _status = AsrModelStatus.inferring;
    try {
      final cleaned = removeDcOffset(chunk.samples);
      final samples = pcm16ToFloat32(cleaned);
      final stream = _recognizer!.createStream();
      stream.acceptWaveform(
        samples: samples,
        sampleRate: chunk.sampleRate,
      );
      _recognizer!.decode(stream);
      final result = _recognizer!.getResult(stream);
      final raw = result.text;
      stream.free();

      final text = normalizeTranscript(raw);
      _status = AsrModelStatus.ready;

      // Reject empty or single-character noise emissions from CTC on silence.
      if (text.isEmpty || _isLikelyHallucination(text, chunk.samples.length)) {
        return AsrResult(
          hypotheses: const [],
          isFinal: true,
          status: AsrModelStatus.ready,
          errorMessage: 'rejected: empty or hallucination-like output',
        );
      }

      return AsrResult(
        hypotheses: [
          AsrHypothesis(
            text: text,
            confidence: 1.0, // CTC greedy — no calibrated score
            startMs: chunk.timestampMs,
            endMs: chunk.timestampMs +
                (chunk.samples.length * 1000) ~/ chunk.sampleRate,
          ),
        ],
        isFinal: true,
        status: AsrModelStatus.ready,
      );
    } catch (e) {
      _status = AsrModelStatus.error;
      _lastError = e.toString();
      return AsrResult(
        hypotheses: const [],
        isFinal: true,
        status: AsrModelStatus.error,
        errorMessage: _lastError,
      );
    }
  }

  /// Heuristic: very short CTC text relative to long quiet audio is likely noise.
  bool _isLikelyHallucination(String text, int sampleCount) {
    final letters = text.replaceAll(RegExp(r'\s+'), '');
    if (letters.isEmpty) return true;
    // Less than 2 Arabic letters for >1s of audio → ignore
    if (letters.length < 2 && sampleCount > 16000) return true;
    // Single isolated letter with no word separator context
    if (letters.length == 1) return true;
    return false;
  }

  /// Accumulate PCM and run recognition on each completed segment.
  /// This is chunk/segment based — not true streaming CTC.
  @override
  Stream<AsrResult> recognizeStream(Stream<AudioChunk> audioStream) {
    final controller = StreamController<AsrResult>();
    final buffer = <int>[];
    const targetSamples = 16000 * 3; // ~3 s segments
    const overlapSamples = 16000 ~/ 2; // 0.5 s overlap
    var baseTimestamp = 0;

    late final StreamSubscription sub;
    sub = audioStream.listen(
      (chunk) async {
        if (buffer.isEmpty) baseTimestamp = chunk.timestampMs;
        buffer.addAll(chunk.samples);

        while (buffer.length >= targetSamples) {
          final segment = buffer.sublist(0, targetSamples);
          // Keep overlap for context
          final keep = buffer.sublist(targetSamples - overlapSamples);
          buffer
            ..clear()
            ..addAll(keep);

          final result = await recognize(
            AudioChunk(
              samples: segment,
              sampleRate: chunk.sampleRate,
              timestampMs: baseTimestamp,
            ),
          );
          baseTimestamp += (targetSamples * 1000) ~/ chunk.sampleRate;
          if (!controller.isClosed) controller.add(result);
        }
      },
      onError: controller.addError,
      onDone: () async {
        if (buffer.isNotEmpty && buffer.length > 1600) {
          // Flush remaining (>0.1 s)
          final result = await recognize(
            AudioChunk(
              samples: List<int>.from(buffer),
              sampleRate: 16000,
              timestampMs: baseTimestamp,
            ),
          );
          if (!controller.isClosed) controller.add(result);
        }
        await controller.close();
      },
      cancelOnError: false,
    );

    controller.onCancel = () async {
      await sub.cancel();
    };

    return controller.stream;
  }

  @override
  Future<void> dispose() async {
    _recognizer?.free();
    _recognizer = null;
    _status = AsrModelStatus.notPresent;
  }
}
