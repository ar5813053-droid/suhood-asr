/// Post-ASR reliability checks for quran-asr-small CTC output.
///
/// The model is a Quranic Arabic CTC decoder. It has no calibrated
/// confidence scores and no language-ID head. When fed Hindi/English
/// speech it may still emit Arabic letters. We therefore use only
/// measurable heuristics that do not invent "confidence %".
///
/// Thresholds (documented, tunable via [AsrValidationConfig]):
/// - minLetters: reject 1-letter noise (chosen from silence tests in M2.1)
/// - maxLettersPerSecond: >12 Arabic letters/s of audio is atypical for
///   natural tartil and often indicates CTC garbage on noise
/// - minSpeechSeconds: very short bursts often are noise clicks
/// - rejectLatinMixed: if Latin letters appear in "Arabic" output, reject
library;

class AsrValidationConfig {
  final int minLetters;
  final int maxLetters;
  final double maxLettersPerSecond;
  final double minSpeechSeconds;
  final bool rejectLatinMixed;

  const AsrValidationConfig({
    this.minLetters = 2,
    this.maxLetters = 400,
    this.maxLettersPerSecond = 12.0,
    this.minSpeechSeconds = 0.35,
    this.rejectLatinMixed = true,
  });
}

enum AsrValidationDecision {
  accepted,
  rejected,
  uncertain,
}

class AsrValidationResult {
  final AsrValidationDecision decision;
  final String rawText;
  final String? filteredText;
  final String reason;

  const AsrValidationResult({
    required this.decision,
    required this.rawText,
    this.filteredText,
    required this.reason,
  });

  bool get isPublishable =>
      decision == AsrValidationDecision.accepted ||
      decision == AsrValidationDecision.uncertain;
}

class AsrOutputValidator {
  AsrOutputValidator({AsrValidationConfig? config})
      : config = config ?? const AsrValidationConfig();

  final AsrValidationConfig config;

  /// Arabic letter range (basic + presentation forms commonly seen).
  static final _arabicLetter = RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]');
  static final _latinLetter = RegExp(r'[A-Za-z]');

  AsrValidationResult validate({
    required String rawText,
    required int sampleCount,
    required int sampleRate,
  }) {
    final raw = rawText.trim();
    if (raw.isEmpty) {
      return const AsrValidationResult(
        decision: AsrValidationDecision.rejected,
        rawText: '',
        reason: 'empty output',
      );
    }

    final durationSec =
        sampleRate > 0 ? sampleCount / sampleRate : 0.0;

    if (durationSec > 0 && durationSec < config.minSpeechSeconds) {
      return AsrValidationResult(
        decision: AsrValidationDecision.rejected,
        rawText: raw,
        reason: 'audio too short (${durationSec.toStringAsFixed(2)}s)',
      );
    }

    final lettersOnly = raw.replaceAll(RegExp(r'\s+'), '');
    final arabicCount = _arabicLetter.allMatches(lettersOnly).length;
    final latinCount = _latinLetter.allMatches(raw).length;

    if (config.rejectLatinMixed && latinCount > 0) {
      return AsrValidationResult(
        decision: AsrValidationDecision.rejected,
        rawText: raw,
        reason: 'latin characters in output ($latinCount)',
      );
    }

    if (arabicCount < config.minLetters) {
      return AsrValidationResult(
        decision: AsrValidationDecision.rejected,
        rawText: raw,
        reason: 'too few Arabic letters ($arabicCount)',
      );
    }

    if (arabicCount > config.maxLetters) {
      return AsrValidationResult(
        decision: AsrValidationDecision.rejected,
        rawText: raw,
        reason: 'implausibly long token run ($arabicCount)',
      );
    }

    if (durationSec > 0.5) {
      final rate = arabicCount / durationSec;
      if (rate > config.maxLettersPerSecond) {
        return AsrValidationResult(
          decision: AsrValidationDecision.uncertain,
          rawText: raw,
          filteredText: raw,
          reason:
              'high letter rate ${rate.toStringAsFixed(1)}/s (possible non-Arabic speech)',
        );
      }
    }

    // Single repeated character spam (e.g. ا ا ا ا)
    final words = raw.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length >= 4) {
      final allSame = words.every((w) => w == words.first);
      if (allSame && words.first.length <= 2) {
        return AsrValidationResult(
          decision: AsrValidationDecision.rejected,
          rawText: raw,
          reason: 'repeated single-token spam',
        );
      }
    }

    return AsrValidationResult(
      decision: AsrValidationDecision.accepted,
      rawText: raw,
      filteredText: raw,
      reason: 'ok',
    );
  }
}
