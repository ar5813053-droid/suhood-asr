/// Surah and Ayah matching interfaces for Suhood-AlQuran-STT.
///
/// The matcher receives ASR output and tries to locate the corresponding
/// Quranic location. It never invents results; low-confidence matches
/// must be reported as unmatched.
library;

import '../asr/asr_engine.dart';
import '../quran/quran_text.dart';

/// A candidate match of recognized text to a Quran location.
class MatchCandidate {
  final int surah;
  final int ayah;
  final double score; // 0.0 – 1.0
  final String matchedText;
  final int startWordIndex;
  final int endWordIndex;

  const MatchCandidate({
    required this.surah,
    required this.ayah,
    required this.score,
    required this.matchedText,
    this.startWordIndex = 0,
    this.endWordIndex = 0,
  });

  String get key => '$surah:$ayah';
}

/// Result of a matching attempt.
class MatchResult {
  /// Best candidate, or null when confidence is too low.
  final MatchCandidate? best;

  /// All candidates above a minimum threshold, sorted by score desc.
  final List<MatchCandidate> candidates;

  /// Whether the matcher is confident enough to surface a result.
  final bool isConfident;

  /// Human-readable reason when no match (e.g. "low score", "empty transcript").
  final String? reason;

  const MatchResult({
    this.best,
    this.candidates = const [],
    this.isConfident = false,
    this.reason,
  });
}

/// Configuration for the matcher.
class MatcherConfig {
  /// Minimum score required to consider a match confident.
  final double confidenceThreshold;

  /// Maximum number of candidates to keep.
  final int maxCandidates;

  /// Whether to allow matches across Surah boundaries.
  final bool allowCrossSurah;

  const MatcherConfig({
    this.confidenceThreshold = 0.75,
    this.maxCandidates = 5,
    this.allowCrossSurah = false,
  });
}

/// Abstract Surah/Ayah matcher.
abstract class AyahMatcher {
  String get name;

  /// Prepare any indexes needed for fast lookup.
  Future<void> initialize(QuranTextProvider quran, MatcherConfig config);

  /// Match a single ASR hypothesis (or partial transcript).
  Future<MatchResult> match(AsrHypothesis hypothesis);

  /// Match a stream of partial ASR results (for live tracking).
  Stream<MatchResult> matchStream(Stream<AsrHypothesis> hypotheses);

  Future<void> dispose();
}

/// Stub matcher for Milestone 1.
/// Always returns "no match" so the UI never shows fabricated Surah/Ayah.
class StubAyahMatcher implements AyahMatcher {
  @override
  String get name => 'StubAyahMatcher';

  @override
  Future<void> initialize(QuranTextProvider quran, MatcherConfig config) async {
    // No-op. Real matchers will build inverted indexes here.
  }

  @override
  Future<MatchResult> match(AsrHypothesis hypothesis) async {
    return const MatchResult(
      isConfident: false,
      reason: 'Matcher not implemented (Milestone 1 placeholder)',
    );
  }

  @override
  Stream<MatchResult> matchStream(Stream<AsrHypothesis> hypotheses) {
    return Stream.value(
      const MatchResult(
        isConfident: false,
        reason: 'Matcher not implemented (Milestone 1 placeholder)',
      ),
    );
  }

  @override
  Future<void> dispose() async {}
}
