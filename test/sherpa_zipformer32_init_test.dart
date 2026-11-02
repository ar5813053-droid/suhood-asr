import 'package:flutter_test/flutter_test.dart';
import 'package:suhood_asr/engine/asr/sherpa_zipformer_quran32.dart';
import 'package:suhood_asr/engine/asr/zipformer32_model_store.dart';
import 'package:suhood_asr/engine/audio/audio_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SherpaZipformerQuran32Engine init guards', () {
    test('fails when files not verified', () async {
      final store = Zipformer32ModelStore();
      final engine = SherpaZipformerQuran32Engine(store: store);
      final r = await engine.initializeFromStore();
      expect(r.success, isFalse);
      expect(r.message, contains('not imported'));
      expect(engine.isInitialized, isFalse);
      expect(store.isReadyForInference, isFalse);
      await engine.dispose();
    });

    test('recognize before init returns error result', () async {
      final store = Zipformer32ModelStore();
      final engine = SherpaZipformerQuran32Engine(store: store);
      final res = await engine.recognize(
        const AudioChunk(samples: [0, 0, 0], sampleRate: 16000),
      );
      expect(res.hypotheses, isEmpty);
      expect(res.errorMessage, isNotNull);
      await engine.dispose();
    });

    test('dispose is safe when never initialized', () async {
      final store = Zipformer32ModelStore();
      final engine = SherpaZipformerQuran32Engine(store: store);
      await engine.dispose();
      expect(engine.isInitialized, isFalse);
    });
  });

  group('Ready flag coupling', () {
    test('store inferenceInitialized defaults false', () {
      final store = Zipformer32ModelStore();
      expect(store.isReadyForInference, isFalse);
      store.inferenceInitialized = true;
      expect(store.isReadyForInference, isTrue);
      store.inferenceInitialized = false;
      expect(store.isReadyForInference, isFalse);
    });
  });
}
