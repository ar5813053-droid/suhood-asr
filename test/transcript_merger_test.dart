import 'package:flutter_test/flutter_test.dart';
import 'package:suhood_asr/engine/asr/transcript_merger.dart';

void main() {
  group('TranscriptMerger', () {
    test('first segment', () {
      final m = TranscriptMerger();
      final d = m.append('قُلْ هُوَ ٱللَّهُ');
      expect(d.overlapWords, 0);
      expect(m.text, contains('قُلْ'));
    });

    test('overlapping chunks remove artificial duplicate', () {
      final m = TranscriptMerger();
      m.append('الله الصمد');
      final d = m.append('الصمد لم يلد');
      expect(d.overlapWords, 1);
      expect(m.text, 'الله الصمد لم يلد');
      // الصمد only once
      expect(RegExp(r'الصمد').allMatches(m.text).length, 1);
    });

    test('no overlap concatenates', () {
      final m = TranscriptMerger();
      m.append('بسم الله');
      final d = m.append('الرحمن الرحيم');
      expect(d.overlapWords, 0);
      expect(m.text, 'بسم الله الرحمن الرحيم');
    });

    test('genuine consecutive repeat inside one segment is kept', () {
      final m = TranscriptMerger();
      m.append('الله الله أكبر');
      expect(m.text, 'الله الله أكبر');
    });

    test('empty incoming is no-op', () {
      final m = TranscriptMerger();
      m.append('الحمد');
      final d = m.append('   ');
      expect(d.appendedWords, isEmpty);
      expect(m.text, 'الحمد');
    });

    test('clear resets', () {
      final m = TranscriptMerger();
      m.append('أحد');
      m.clear();
      expect(m.text, isEmpty);
    });
  });
}
