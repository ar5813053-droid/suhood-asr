import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:suhood_asr/engine/audio/audio_source.dart';
import 'package:suhood_asr/engine/audio/mic_audio_source.dart';
import 'package:suhood_asr/engine/audio/speech_gate.dart';

List<int> silence({int samples = 16000}) => List<int>.filled(samples, 0);

List<int> lowNoise({int samples = 16000, int amp = 40}) {
  final r = math.Random(1);
  return List<int>.generate(samples, (_) => r.nextInt(amp * 2) - amp);
}

List<int> tone({int samples = 16000, double freq = 220, double amp = 0.25}) {
  final out = <int>[];
  for (var i = 0; i < samples; i++) {
    final v = amp * math.sin(2 * math.pi * freq * i / 16000);
    out.add((v * 32767).round().clamp(-32768, 32767));
  }
  return out;
}

void main() {
  group('isValidPcmForAsr', () {
    test('rejects empty and wrong rate', () {
      expect(
        isValidPcmForAsr(const AudioChunk(samples: [], sampleRate: 16000)),
        isFalse,
      );
      expect(
        isValidPcmForAsr(
          AudioChunk(samples: List.filled(2000, 100), sampleRate: 8000),
        ),
        isFalse,
      );
    });

    test('rejects all zeros', () {
      expect(
        isValidPcmForAsr(
          AudioChunk(samples: silence(samples: 8000), sampleRate: 16000),
        ),
        isFalse,
      );
    });

    test('accepts non-silent 16 kHz mono', () {
      expect(
        isValidPcmForAsr(
          AudioChunk(samples: tone(samples: 8000), sampleRate: 16000),
        ),
        isTrue,
      );
    });
  });

  group('SpeechGate silence rejection', () {
    test('rejects pure silence segment', () {
      final gate = SpeechGate();
      final ok = gate.shouldRecognizeSegment(silence(samples: 48000), finalFlush: false);
      expect(ok, isFalse);
      expect(gate.segmentsRejected, greaterThan(0));
    });

    test('rejects low-level background noise', () {
      final gate = SpeechGate();
      // Warm noise floor
      gate.processSamples(lowNoise(samples: 16000, amp: 30));
      final ok = gate.shouldRecognizeSegment(
        lowNoise(samples: 48000, amp: 30),
        finalFlush: false,
      );
      expect(ok, isFalse);
    });

    test('accepts strong speech-like energy', () {
      final gate = SpeechGate();
      // Establish low noise floor first
      gate.processSamples(lowNoise(samples: 16000, amp: 20));
      final speech = tone(samples: 48000, amp: 0.3);
      final ok = gate.shouldRecognizeSegment(speech, finalFlush: false);
      expect(ok, isTrue);
      expect(gate.segmentsAccepted, greaterThan(0));
    });

    test('rejects very short segments', () {
      final gate = SpeechGate();
      final ok = gate.shouldRecognizeSegment(tone(samples: 800), finalFlush: true);
      expect(ok, isFalse);
    });
  });

  group('removeDcOffset', () {
    test('subtracts mean', () {
      final inSamples = List<int>.generate(100, (i) => 100 + (i % 5));
      final out = removeDcOffset(inSamples);
      final mean = out.reduce((a, b) => a + b) / out.length;
      expect(mean.abs(), lessThan(2));
    });
  });

  group('pcm helpers', () {
    test('pcm16BytesToSamples', () {
      final bytes = Uint8List.fromList([0x00, 0x10, 0xFF, 0x7F]);
      final samples = pcm16BytesToSamples(bytes);
      expect(samples[0], 4096);
      expect(samples[1], 32767);
    });
  });

  group('SpeechGate calibration', () {
    test('rejects segments during calibration', () {
      final gate = SpeechGate(
        config: const SpeechGateConfig(calibrationSamples: 32000),
      );
      gate.processSamples(List<int>.filled(8000, 0));
      expect(gate.isCalibrating, isTrue);
      final ok = gate.shouldRecognizeSegment(
        List<int>.filled(16000, 1000),
        finalFlush: false,
      );
      expect(ok, isFalse);
    });

    test('leaves calibration after enough samples', () {
      final gate = SpeechGate(
        config: const SpeechGateConfig(calibrationSamples: 8000),
      );
      gate.processSamples(List<int>.filled(8000, 20));
      expect(gate.isCalibrating, isFalse);
      expect(gate.state, SpeechState.silence);
    });
  });

}
