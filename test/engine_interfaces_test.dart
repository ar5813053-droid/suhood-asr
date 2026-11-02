import 'package:flutter_test/flutter_test.dart';
import 'package:suhood_asr/engine/asr/asr_engine.dart';
import 'package:suhood_asr/engine/audio/audio_source.dart';
import 'package:suhood_asr/engine/matcher/ayah_matcher.dart';
import 'package:suhood_asr/engine/qiraat/qiraat.dart';
import 'package:suhood_asr/engine/quran/quran_text.dart';

void main() {
  group('StubAudioSource', () {
    test('starts and stops without emitting audio', () async {
      final source = StubAudioSource();
      expect(source.name, 'StubAudioSource');
      expect(source.isCapturing, isFalse);

      final stream = source.start(const AudioCaptureConfig());
      expect(source.isCapturing, isTrue);

      // Stream is empty by design.
      final events = await stream.toList();
      expect(events, isEmpty);

      await source.stop();
      expect(source.isCapturing, isFalse);
      await source.dispose();
    });
  });

  group('StubAsrEngine', () {
    test('reports notPresent and returns empty result', () async {
      final engine = StubAsrEngine();
      expect(engine.name, 'StubAsrEngine');
      expect(engine.status, AsrModelStatus.notPresent);

      await engine.initialize(const AsrConfig());
      expect(engine.status, AsrModelStatus.notPresent);

      final result = await engine.recognize(
        const AudioChunk(samples: [], sampleRate: 16000),
      );
      expect(result.hypotheses, isEmpty);
      expect(result.isFinal, isTrue);
      expect(result.errorMessage, contains('not loaded'));
      await engine.dispose();
    });
  });

  group('StubQuranTextProvider', () {
    test('provides Al-Fatiha only', () async {
      final provider = StubQuranTextProvider();
      await provider.initialize();
      expect(provider.surahCount, 1);
      expect(provider.surahs.first.nameEnglish, 'Al-Fatiha');

      final ayah = provider.getAyah(1, 1);
      expect(ayah, isNotNull);
      expect(ayah!.text, contains('بِسْمِ'));

      expect(provider.getAyah(2, 1), isNull); // no full Quran in stub
      await provider.dispose();
    });
  });

  group('StubAyahMatcher', () {
    test('never invents a match', () async {
      final matcher = StubAyahMatcher();
      final quran = StubQuranTextProvider();
      await quran.initialize();
      await matcher.initialize(quran, const MatcherConfig());

      final result = await matcher.match(
        const AsrHypothesis(text: 'anything', confidence: 1.0),
      );
      expect(result.isConfident, isFalse);
      expect(result.best, isNull);
      expect(result.reason, contains('not implemented'));
      await matcher.dispose();
    });
  });

  group('StubQiraatSelector', () {
    test('defaults to Hafs and can select it', () async {
      final selector = StubQiraatSelector();
      expect(selector.current.id, 'hafs-an-asim');
      final ok = await selector.select('hafs-an-asim');
      expect(ok, isTrue);
      final bad = await selector.select('nonexistent');
      expect(bad, isFalse);
      await selector.dispose();
    });
  });
}
