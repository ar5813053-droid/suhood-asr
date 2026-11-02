/// Real Android microphone capture using the `record` package.
/// Produces 16 kHz mono PCM chunks suitable for the Quran ASR model.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'audio_source.dart';

/// Converts interleaved PCM16 bytes to a list of sample values (-32768..32767).
List<int> pcm16BytesToSamples(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  final samples = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    samples.add(bd.getInt16(i, Endian.little));
  }
  return samples;
}

/// RMS amplitude in [0.0, 1.0] for UI level metering.
double pcm16RmsLevel(List<int> samples) {
  if (samples.isEmpty) return 0.0;
  var sum = 0.0;
  for (final s in samples) {
    final v = s / 32768.0;
    sum += v * v;
  }
  final rms = (sum / samples.length);
  // Soft clip for display
  return (rms * 4.0).clamp(0.0, 1.0);
}

/// Real microphone [AudioSource] backed by `package:record`.
class MicAudioSource implements AudioSource {
  final AudioRecorder _recorder = AudioRecorder();
  StreamController<AudioChunk>? _controller;
  StreamSubscription<Uint8List>? _sub;
  bool _capturing = false;

  /// Latest RMS level 0..1 (updated while capturing).
  double level = 0.0;

  @override
  String get name => 'MicAudioSource';

  @override
  bool get isCapturing => _capturing;

  /// Request RECORD_AUDIO permission. Returns true if granted.
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> hasPermission() async {
    return Permission.microphone.isGranted;
  }

  @override
  Stream<AudioChunk> start(AudioCaptureConfig config) {
    if (_capturing) {
      throw StateError('Already capturing');
    }
    // config reserved for future buffer sizing
    _controller = StreamController<AudioChunk>.broadcast();
    _startInternal();
    return _controller!.stream;
  }

  Future<void> _startInternal() async {
    try {
      final granted = await requestPermission();
      if (!granted) {
        _controller?.addError(
          StateError('Microphone permission denied'),
        );
        await stop();
        return;
      }

      // Stream PCM16 at 16 kHz mono.
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
        ),
      );

      _capturing = true;
      var timestampMs = 0;
      const bytesPerSecond = 16000 * 2; // pcm16 mono

      _sub = stream.listen(
        (Uint8List data) {
          if (!_capturing || data.isEmpty) return;
          final samples = pcm16BytesToSamples(data);
          level = pcm16RmsLevel(samples);
          final chunk = AudioChunk(
            samples: samples,
            sampleRate: 16000,
            channels: 1,
            format: 'pcm16',
            timestampMs: timestampMs,
          );
          timestampMs += (data.length * 1000) ~/ bytesPerSecond;
          _controller?.add(chunk);
        },
        onError: (Object e, StackTrace st) {
          _controller?.addError(e, st);
        },
        onDone: () {
          _capturing = false;
        },
      );
    } catch (e, st) {
      _controller?.addError(e, st);
      await stop();
    }
  }

  @override
  Future<void> stop() async {
    _capturing = false;
    await _sub?.cancel();
    _sub = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
    level = 0.0;
    await _controller?.close();
    _controller = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }
}
