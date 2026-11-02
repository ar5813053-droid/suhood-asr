/// Qira'at (canonical readings) interfaces for Suhood-AlQuran-STT.
///
/// Future support for different Qira'at, Riwayat, and regional
/// pronunciation variants will plug in through these abstractions.
library;

/// A named Qira'ah / Riwayah pair.
class QiraatVariant {
  final String id; // e.g. 'hafs-an-asim'
  final String nameArabic;
  final String nameEnglish;
  final String narrator; // e.g. 'Hafs'
  final String from; // e.g. 'Asim'

  const QiraatVariant({
    required this.id,
    required this.nameArabic,
    required this.nameEnglish,
    required this.narrator,
    required this.from,
  });
}

/// Known variants that the engine may eventually support.
/// Only Hafs is listed for now; others are placeholders for the roadmap.
const List<QiraatVariant> knownQiraat = [
  QiraatVariant(
    id: 'hafs-an-asim',
    nameArabic: 'حفص عن عاصم',
    nameEnglish: 'Hafs an Asim',
    narrator: 'Hafs',
    from: 'Asim',
  ),
  // Future: Warsh, Qalun, Al-Duri, etc.
];

/// Interface for selecting and applying a Qira'at variant.
///
/// In later milestones this will influence both the expected text
/// used by the matcher and (optionally) pronunciation models.
abstract class QiraatSelector {
  /// Currently active variant.
  QiraatVariant get current;

  /// All variants the implementation knows about.
  List<QiraatVariant> get available;

  /// Switch to a different variant. Returns false if unsupported.
  Future<bool> select(String variantId);

  Future<void> dispose();
}

/// Simple stub that only supports Hafs.
class StubQiraatSelector implements QiraatSelector {
  QiraatVariant _current = knownQiraat.first;

  @override
  QiraatVariant get current => _current;

  @override
  List<QiraatVariant> get available => List.unmodifiable(knownQiraat);

  @override
  Future<bool> select(String variantId) async {
    final match = knownQiraat.where((v) => v.id == variantId);
    if (match.isEmpty) return false;
    _current = match.first;
    return true;
  }

  @override
  Future<void> dispose() async {}
}
