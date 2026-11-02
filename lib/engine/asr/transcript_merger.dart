/// Deterministic word-level merger for overlapping ASR segments.
///
/// Algorithm (suffix-prefix overlap):
/// 1. Split previous finalized text and new hypothesis into words.
/// 2. Find the longest k such that the last k words of the previous
///    transcript equal the first k words of the new hypothesis.
/// 3. Append only words after that overlap.
///
/// This removes artificial duplicates from chunk overlap (e.g. الصمد
/// appearing at the end of segment 1 and start of segment 2).
///
/// Limitation: if the speaker genuinely repeats the exact same phrase
/// that also sits on a chunk boundary, one repetition may be absorbed
/// into the overlap. We mitigate by requiring overlap words to be
/// contiguous at the boundary only — internal genuine repeats are kept.
///
/// We do NOT delete consecutive identical words inside a single
/// hypothesis (اَللَّه اَللَّه is preserved).
library;

class MergeDecision {
  final String mergedText;
  final int overlapWords;
  final List<String> appendedWords;
  final String note;

  const MergeDecision({
    required this.mergedText,
    required this.overlapWords,
    required this.appendedWords,
    required this.note,
  });
}

class TranscriptMerger {
  String _finalized = '';
  final List<MergeDecision> history = [];

  String get text => _finalized;

  void clear() {
    _finalized = '';
    history.clear();
  }

  /// Merge [incoming] into the running transcript.
  MergeDecision append(String incoming) {
    final next = incoming
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (next.isEmpty) {
      return MergeDecision(
        mergedText: _finalized,
        overlapWords: 0,
        appendedWords: const [],
        note: 'empty incoming',
      );
    }

    if (_finalized.isEmpty) {
      _finalized = next.join(' ');
      final d = MergeDecision(
        mergedText: _finalized,
        overlapWords: 0,
        appendedWords: next,
        note: 'first segment',
      );
      history.add(d);
      return d;
    }

    final existing =
        _finalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    // Longest suffix-prefix match, capped so we never absorb the entire
    // previous transcript into "overlap".
    final maxK = existing.length < next.length ? existing.length : next.length;
    // Cap: at most half of the new segment, and at most 6 words
    final cap = (next.length ~/ 2).clamp(0, 6);
    final limit = maxK < cap ? maxK : cap;

    var overlap = 0;
    for (var k = limit; k > 0; k--) {
      final tail = existing.sublist(existing.length - k);
      final head = next.sublist(0, k);
      if (_listsEqual(tail, head)) {
        overlap = k;
        break;
      }
    }

    final appended = next.sublist(overlap);
    if (appended.isNotEmpty) {
      _finalized = '$_finalized ${appended.join(' ')}'.trim();
    }

    final d = MergeDecision(
      mergedText: _finalized,
      overlapWords: overlap,
      appendedWords: appended,
      note: overlap > 0 ? 'suffix-prefix overlap=$overlap' : 'no overlap',
    );
    history.add(d);
    return d;
  }

  static bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
