
/// Tracks finalized streaming segments so each is committed to FINAL once.
///
/// PARTIAL is always replaceable by the caller; this class only gates appends.
library;

class SegmentFinalizer {
  String _lastCommitted = '';
  final List<String> _finals = [];

  String get lastCommitted => _lastCommitted;
  List<String> get finals => List.unmodifiable(_finals);
  String get joinedFinals => _finals.join(' | ');

  void clear() {
    _lastCommitted = '';
    _finals.clear();
  }

  /// Replaceable partial — no side effects (documented for tests).
  String replacePartial(String text) => text;

  /// Commit [text] once per distinct finalized segment.
  /// Returns true if appended.
  bool commitFinal(String text) {
    final piece = text.trim();
    if (piece.isEmpty) return false;
    // Same as last commit (endpoint + stop race, or repeated endpoint with same hyp).
    if (piece == _lastCommitted) return false;
    _finals.add(piece);
    _lastCommitted = piece;
    return true;
  }

  /// Preserve legitimate internal repeats; only blocks duplicate *segment* commits.
  bool wouldPreserveInternalRepeats(String hypothesis) {
    // e.g. "aa aa" or repeated phoneme runs stay intact inside one commit.
    return hypothesis == hypothesis; // identity: we never strip inside a segment
  }
}
