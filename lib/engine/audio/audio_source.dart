/// Audio processing interfaces for Suhood-AlQuran-STT.
///
/// These abstractions keep microphone capture, buffering, and
/// feature extraction independent of the ASR engine.
library;

/// Represents a chunk of raw PCM audio data.
class AudioChunk {
  /// 16-bit PCM samples (little-endian) or float32 depending on [format].
  final List<int> samples;

  /// Sample rate in Hz (e.g. 16000).
  final int sampleRate;

  /// Number of channels (1 = mono).
  final int channels;

  /// Format identifier: 'pcm16' or 'float32'.
  final String format;

  /// Timestamp of the first sample relative to recording start (ms).
  final int timestampMs;

  const AudioChunk({
    required this.samples,
    required this.sampleRate,
    this.channels = 1,
    this.format = 'pcm16',
    this.timestampMs = 0,
  });
}

/// Configuration for an audio capture session.
class AudioCaptureConfig {
  final int sampleRate;
  final int channels;
  final int bufferSizeMs;
  final bool echoCancellation;
  final bool noiseSuppression;

  const AudioCaptureConfig({
    this.sampleRate = 16000,
    this.channels = 1,
    this.bufferSizeMs = 100,
    this.echoCancellation = true,
    this.noiseSuppression = true,
  });
}

/// Abstract interface for audio input sources (microphone, file, stream).
abstract class AudioSource {
  /// Human-readable name of this source implementation.
  String get name;

  /// Whether the source is currently capturing.
  bool get isCapturing;

  /// Start capturing audio according to [config].
  /// Returns a stream of [AudioChunk]s.
  Stream<AudioChunk> start(AudioCaptureConfig config);

  /// Stop capturing and release resources.
  Future<void> stop();

  /// Dispose any held resources. After dispose the instance must not be reused.
  Future<void> dispose();
}

/// Placeholder implementation used until a real microphone source is wired.
/// Does not capture real audio; exists only so the UI can be developed.
class StubAudioSource implements AudioSource {
  bool _capturing = false;

  @override
  String get name => 'StubAudioSource';

  @override
  bool get isCapturing => _capturing;

  @override
  Stream<AudioChunk> start(AudioCaptureConfig config) {
    _capturing = true;
    // Emit nothing. Real implementations will push PCM frames.
    return const Stream<AudioChunk>.empty();
  }

  @override
  Future<void> stop() async {
    _capturing = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}
