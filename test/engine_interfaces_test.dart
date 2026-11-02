import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:suhood_asr/engine/asr/asr_engine.dart';
import 'package:suhood_asr/engine/asr/model_manager.dart';
import 'package:suhood_asr/engine/audio/audio_source.dart';
import 'package:suhood_asr/engine/audio/mic_audio_source.dart';
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

      final events = await stream.toList();
      expect(events, isEmpty);

      await source.stop();
      expect(source.isCapturing, isFalse);
      await source.dispose();
    });
  });

  group('PCM helpers', () {
    test('pcm16BytesToSamples converts little-endian', () {
      // 0x00 0x10 = 4096
      final bytes = Uint8List.fromList([0x00, 0x10, 0xFF, 0x7F]);
      final samples = pcm16BytesToSamples(bytes);
      expect(samples.length, 2);
      expect(samples[0], 4096);
      expect(samples[1], 32767);
    });

    test('pcm16RmsLevel is in range', () {
      expect(pcm16RmsLevel([]), 0.0);
      expect(pcm16RmsLevel([0, 0, 0]), 0.0);
      final level = pcm16RmsLevel([16000, -16000, 8000]);
      expect(level, greaterThan(0.0));
      expect(level, lessThanOrEqualTo(1.0));
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

  group('ModelManager URLs', () {
    test('points at Abdou/quran-asr-small', () {
      expect(QuranAsrModelFiles.repo, 'Abdou/quran-asr-small');
      expect(QuranAsrModelFiles.modelFileName, 'model.int8.onnx');
      expect(QuranAsrModelFiles.tokensFileName, 'tokens.txt');
      expect(QuranAsrModelFiles.modelUrl, contains('huggingface.co'));
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

      expect(provider.getAyah(2, 1), isNull);
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
