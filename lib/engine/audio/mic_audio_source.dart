/// Real Android microphone capture via platform channel (AudioRecord).
/// Produces 16 kHz mono PCM chunks suitable for the Quran ASR model.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'audio_source.dart';

/// Converts interleaved PCM16 bytes to sample values.
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
  final rms = sum / samples.length;
  return (rms * 4.0).clamp(0.0, 1.0);
}

/// Real microphone [AudioSource] using Android AudioRecord (platform channel).
class MicAudioSource implements AudioSource {
  static const _method = MethodChannel('com.suhood.asr/audio');
  static const _events = EventChannel('com.suhood.asr/audio_stream');

  StreamController<AudioChunk>? _controller;
  StreamSubscription<dynamic>? _sub;
  bool _capturing = false;
  double level = 0.0;
  int _timestampMs = 0;

  @override
  String get name => 'MicAudioSource';

  @override
  bool get isCapturing => _capturing;

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
    _controller = StreamController<AudioChunk>.broadcast();
    _timestampMs = 0;
    _startInternal();
    return _controller!.stream;
  }

  Future<void> _startInternal() async {
    try {
      final granted = await requestPermission();
      if (!granted) {
        _controller?.addError(StateError('Microphone permission denied'));
        await stop();
        return;
      }

      _sub = _events.receiveBroadcastStream().listen(
        (dynamic event) {
          if (!_capturing || event == null) return;
          final samples = (event as List).cast<int>();
          if (samples.isEmpty) return;
          level = pcm16RmsLevel(samples);
          final chunk = AudioChunk(
            samples: samples,
            sampleRate: 16000,
            channels: 1,
            format: 'pcm16',
            timestampMs: _timestampMs,
          );
          _timestampMs += (samples.length * 1000) ~/ 16000;
          _controller?.add(chunk);
        },
        onError: (Object e, StackTrace st) {
          _controller?.addError(e, st);
        },
      );

      await _method.invokeMethod<bool>('start');
      _capturing = true;
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
      await _method.invokeMethod<bool>('stop');
    } catch (_) {}
    level = 0.0;
    await _controller?.close();
    _controller = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}
