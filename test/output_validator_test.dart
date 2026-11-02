import 'package:flutter_test/flutter_test.dart';
import 'package:suhood_asr/engine/asr/output_validator.dart';

void main() {
  final v = AsrOutputValidator();

  group('AsrOutputValidator', () {
    test('rejects empty', () {
      final r = v.validate(rawText: '', sampleCount: 16000, sampleRate: 16000);
      expect(r.decision, AsrValidationDecision.rejected);
    });

    test('rejects one letter', () {
      final r = v.validate(rawText: 'ا', sampleCount: 16000, sampleRate: 16000);
      expect(r.decision, AsrValidationDecision.rejected);
    });

    test('accepts normal Arabic phrase', () {
      final r = v.validate(
        rawText: 'قُلْ هُوَ ٱللَّهُ أَحَدٌ',
        sampleCount: 32000,
        sampleRate: 16000,
      );
      expect(r.decision, AsrValidationDecision.accepted);
    });

    test('rejects latin mixed (e.g. Hindi/English garbage path)', () {
      final r = v.validate(
        rawText: 'hello الله',
        sampleCount: 32000,
        sampleRate: 16000,
      );
      expect(r.decision, AsrValidationDecision.rejected);
      expect(r.reason, contains('latin'));
    });

    test('flags high letter rate as uncertain', () {
      // 40 letters in 1 second → rate 40 > 12
      final spam = List.filled(40, 'م').join();
      final r = v.validate(
        rawText: spam,
        sampleCount: 16000,
        sampleRate: 16000,
      );
      expect(
        r.decision == AsrValidationDecision.uncertain ||
            r.decision == AsrValidationDecision.rejected,
        isTrue,
      );
    });

    test('rejects short audio', () {
      final r = v.validate(
        rawText: 'الله أحد',
        sampleCount: 1600, // 0.1 s
        sampleRate: 16000,
      );
      expect(r.decision, AsrValidationDecision.rejected);
    });
  });
}
