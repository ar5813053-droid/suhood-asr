/// Speech recognition interfaces for Suhood-AlQuran-STT.
///
/// The ASR engine is deliberately independent of Quran matching and
/// audio capture so that different models (Whisper, Wav2Vec, custom
/// CTC, etc.) can be swapped without touching the rest of the stack.
library;

import '../audio/audio_source.dart';

/// A single recognition hypothesis for a segment of audio.
class AsrHypothesis {
  /// The recognized text (Arabic script expected for Quranic models).
  final String text;

  /// Confidence score in [0.0, 1.0]. Higher is better.
  final double confidence;

  /// Start time relative to the beginning of the utterance (ms).
  final int startMs;

  /// End time relative to the beginning of the utterance (ms).
  final int endMs;

  /// Optional word-level timestamps when the model provides them.
  final List<WordTiming>? words;

  const AsrHypothesis({
    required this.text,
    required this.confidence,
    this.startMs = 0,
    this.endMs = 0,
    this.words,
  });
}

/// Word-level timing information.
class WordTiming {
  final String word;
  final int startMs;
  final int endMs;
  final double confidence;

  const WordTiming({
    required this.word,
    required this.startMs,
    required this.endMs,
    this.confidence = 1.0,
  });
}

/// Status of the ASR model lifecycle.
enum AsrModelStatus {
  /// Model weights are not present on device.
  notPresent,

  /// Model is being downloaded or loaded.
  loading,

  /// Model is ready for inference.
  ready,

  /// Model failed to load (see lastError).
  error,

  /// Model is currently running inference.
  inferring,
}

/// Result of a single recognition pass.
class AsrResult {
  final List<AsrHypothesis> hypotheses;
  final bool isFinal;
  final AsrModelStatus status;
  final String? errorMessage;

  const AsrResult({
    required this.hypotheses,
    this.isFinal = false,
    this.status = AsrModelStatus.ready,
    this.errorMessage,
  });

  /// Convenience: best hypothesis text or empty string.
  String get bestText =>
      hypotheses.isEmpty ? '' : hypotheses.first.text;
}

/// Configuration for an ASR engine instance.
class AsrConfig {
  /// Preferred sample rate the model expects.
  final int sampleRate;

  /// Language / dialect hint (e.g. 'ar', 'ar-quran').
  final String language;

  /// Whether to request partial (streaming) results.
  final bool enablePartialResults;

  /// Maximum number of alternative hypotheses to return.
  final int maxAlternatives;

  const AsrConfig({
    this.sampleRate = 16000,
    this.language = 'ar',
    this.enablePartialResults = true,
    this.maxAlternatives = 1,
  });
}

/// Abstract ASR engine.
///
/// Implementations must never invent Quran text. They only produce
/// transcriptions of the audio they are given.
abstract class AsrEngine {
  /// Human-readable name of this engine (e.g. 'WhisperTiny', 'StubAsr').
  String get name;

  /// Current model status.
  AsrModelStatus get status;

  /// Last error message when status == AsrModelStatus.error.
  String? get lastError;

  /// Prepare the model (load from assets / download if permitted).
  /// Must be called before [recognize] or [recognizeStream].
  Future<void> initialize(AsrConfig config);

  /// Run recognition on a complete audio buffer (offline mode).
  Future<AsrResult> recognize(AudioChunk chunk);

  /// Streaming recognition: feed chunks and receive partial / final results.
  Stream<AsrResult> recognizeStream(Stream<AudioChunk> audioStream);

  /// Release model resources.
  Future<void> dispose();
}

/// Stub engine used in Milestone 1.
///
/// Explicitly does not perform speech recognition. The UI shows that
/// the engine is not yet available so users never see fake transcripts.
class StubAsrEngine implements AsrEngine {
  AsrModelStatus _status = AsrModelStatus.notPresent;
  String? _lastError;

  @override
  String get name => 'StubAsrEngine';

  @override
  AsrModelStatus get status => _status;

  @override
  String? get lastError => _lastError;

  @override
  Future<void> initialize(AsrConfig config) async {
    // Intentionally remain "notPresent". Real engines will load models here.
    _status = AsrModelStatus.notPresent;
    _lastError = null;
  }

  @override
  Future<AsrResult> recognize(AudioChunk chunk) async {
    return const AsrResult(
      hypotheses: [],
      isFinal: true,
      status: AsrModelStatus.notPresent,
      errorMessage: 'ASR model not loaded (Milestone 1 placeholder)',
    );
  }

  @override
  Stream<AsrResult> recognizeStream(Stream<AudioChunk> audioStream) {
    return Stream.value(
      const AsrResult(
        hypotheses: [],
        isFinal: false,
        status: AsrModelStatus.notPresent,
        errorMessage: 'ASR model not loaded (Milestone 1 placeholder)',
      ),
    );
  }

  @override
  Future<void> dispose() async {
    _status = AsrModelStatus.notPresent;
  }
}
