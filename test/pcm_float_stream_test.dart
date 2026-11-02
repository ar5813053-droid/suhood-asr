import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:suhood_asr/engine/asr/sherpa_zipformer_quran32.dart';
import 'package:suhood_asr/engine/asr/zipformer32_model_store.dart';

void main() {
  group('pcm16ToFloat32', () {
    test('empty', () {
      expect(pcm16ToFloat32(const []).length, 0);
    });

    test('scales int16 to [-1,1]', () {
      final f = pcm16ToFloat32([0, 32767, -32768, 16384]);
      expect(f[0], closeTo(0.0, 1e-6));
      expect(f[1], closeTo(32767 / 32768.0, 1e-6));
      expect(f[2], closeTo(-1.0, 1e-6));
      expect(f[3], closeTo(0.5, 1e-4));
      expect(f, isA<Float32List>());
    });

    test('preserves length', () {
      final pcm = List<int>.generate(1600, (i) => i % 100);
      expect(pcm16ToFloat32(pcm).length, 1600);
    });
  });

  group('isPcmSilenceOrInvalid', () {
    test('empty is invalid', () {
      expect(isPcmSilenceOrInvalid(const []), isTrue);
    });

    test('near-zero is silence', () {
      expect(isPcmSilenceOrInvalid(List.filled(100, 0)), isTrue);
      expect(isPcmSilenceOrInvalid(List.filled(100, 3)), isTrue);
    });

    test('speech-level energy is not silence', () {
      expect(isPcmSilenceOrInvalid(List.filled(100, 500)), isFalse);
    });
  });

  group('session guards without native model', () {
    test('startSession throws if not initialized', () {
      final store = Zipformer32ModelStore();
      final engine = SherpaZipformerQuran32Engine(store: store);
      expect(() => engine.startSession(), throwsStateError);
    });

    test('acceptPcm16 without session returns null', () {
      final store = Zipformer32ModelStore();
      final engine = SherpaZipformerQuran32Engine(store: store);
      expect(engine.acceptPcm16(List.filled(320, 1000)), isNull);
    });

    test('endSession without session is safe', () {
      final store = Zipformer32ModelStore();
      final engine = SherpaZipformerQuran32Engine(store: store);
      expect(engine.endSession(finalize: false), isNull);
    });
  });
}
