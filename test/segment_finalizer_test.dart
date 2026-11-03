import 'package:flutter_test/flutter_test.dart';
import 'package:suhood_asr/engine/asr/segment_finalizer.dart';
import 'package:suhood_asr/engine/asr/sherpa_zipformer_quran32.dart';

void main() {
  group('SegmentFinalizer', () {
    test('partial replace does not append', () {
      final f = SegmentFinalizer();
      expect(f.replacePartial('a'), 'a');
      expect(f.replacePartial('ab'), 'ab');
      expect(f.finals, isEmpty);
    });

    test('one FINAL commit per distinct segment', () {
      final f = SegmentFinalizer();
      expect(f.commitFinal('بِسْم'), isTrue);
      expect(f.commitFinal('بِسْم'), isFalse); // duplicate
      expect(f.commitFinal('ٱللّه'), isTrue);
      expect(f.joinedFinals, 'بِسْم | ٱللّه');
      expect(f.finals.length, 2);
    });

    test('stop after endpoint does not double-commit', () {
      final f = SegmentFinalizer();
      expect(f.commitFinal('segment-a'), isTrue);
      // simulate stop with same hypothesis
      expect(f.commitFinal('segment-a'), isFalse);
      expect(f.finals.length, 1);
    });

    test('empty not committed', () {
      final f = SegmentFinalizer();
      expect(f.commitFinal(''), isFalse);
      expect(f.commitFinal('   '), isFalse);
    });

    test('legitimate internal repeats preserved in one commit', () {
      final f = SegmentFinalizer();
      const hyp = 'اا اا رَّ حْ';
      expect(f.wouldPreserveInternalRepeats(hyp), isTrue);
      expect(f.commitFinal(hyp), isTrue);
      expect(f.finals.single, hyp);
    });

    test('clear resets', () {
      final f = SegmentFinalizer();
      f.commitFinal('x');
      f.clear();
      expect(f.finals, isEmpty);
      expect(f.commitFinal('x'), isTrue);
    });
  });

  group('PCM continuous delivery helpers', () {
    test('near-silence is still convertible (not dropped at convert layer)', () {
      final quiet = List<int>.filled(160, 2); // near digital quiet
      final f = pcm16ToFloat32(quiet);
      expect(f.length, 160);
      expect(f.every((x) => x.abs() < 0.001), isTrue);
    });

    test('empty pcm is invalid', () {
      expect(isPcmSilenceOrInvalid(const []), isTrue);
    });

    test('sample order preserved in conversion', () {
      final pcm = [100, -100, 200, -200];
      final f = pcm16ToFloat32(pcm);
      expect(f[0] > 0, isTrue);
      expect(f[1] < 0, isTrue);
      expect(f[2].abs() > f[0].abs(), isTrue);
    });
  });
}
