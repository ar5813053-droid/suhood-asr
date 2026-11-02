/// Quran text and metadata interfaces for Suhood-AlQuran-STT.
///
/// Provides canonical Arabic text, Surah/Ayah structure, and
/// metadata needed by the matcher. No ASR or audio logic lives here.
library;

/// A single Ayah (verse).
class Ayah {
  final int surahNumber;
  final int ayahNumber;
  final String text; // Uthmani or simple Arabic script
  final String? translation; // optional English / other

  const Ayah({
    required this.surahNumber,
    required this.ayahNumber,
    required this.text,
    this.translation,
  });

  String get key => '$surahNumber:$ayahNumber';
}

/// Metadata for a Surah.
class SurahInfo {
  final int number;
  final String nameArabic;
  final String nameEnglish;
  final int ayahCount;
  final String revelationType; // 'Meccan' or 'Medinan'

  const SurahInfo({
    required this.number,
    required this.nameArabic,
    required this.nameEnglish,
    required this.ayahCount,
    required this.revelationType,
  });
}

/// Abstract access to Quran text and structure.
///
/// Concrete implementations may load from SQLite, JSON assets, or
/// a remote (but offline-first) cache. They must never invent verses.
abstract class QuranTextProvider {
  /// Number of Surahs (should be 114 for the complete Quran).
  int get surahCount;

  /// Metadata for every Surah, ordered by number.
  List<SurahInfo> get surahs;

  /// Return a single Ayah or null if out of range.
  Ayah? getAyah(int surah, int ayah);

  /// Return all Ayahs of a Surah.
  List<Ayah> getSurahAyahs(int surah);

  /// Search for exact or normalized text matches (used by matcher).
  /// Returns list of (surah, ayah) keys that contain the query.
  List<String> searchText(String query, {bool normalized = true});

  /// Load / open the underlying data store.
  Future<void> initialize();

  /// Release resources.
  Future<void> dispose();
}

/// Minimal in-memory stub containing only Al-Fatiha for testing UI flow.
/// Real data will be added in a later milestone from an authentic source.
class StubQuranTextProvider implements QuranTextProvider {
  static const List<SurahInfo> _surahs = [
    SurahInfo(
      number: 1,
      nameArabic: 'الفاتحة',
      nameEnglish: 'Al-Fatiha',
      ayahCount: 7,
      revelationType: 'Meccan',
    ),
  ];

  // Only Al-Fatiha is present so that no one mistakes this for a full Quran.
  static const Map<String, String> _ayahs = {
    '1:1': 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
    '1:2': 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ',
    '1:3': 'ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
    '1:4': 'مَٰلِكِ يَوْمِ ٱلدِّينِ',
    '1:5': 'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ',
    '1:6': 'ٱهْدِنَا ٱلصِّرَٰطَ ٱلْمُسْتَقِيمَ',
    '1:7':
        'صِرَٰطَ ٱلَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ ٱلْمَغْضُوبِ عَلَيْهِمْ وَلَا ٱلضَّآلِّينَ',
  };

  bool _ready = false;

  @override
  int get surahCount => _surahs.length;

  @override
  List<SurahInfo> get surahs => List.unmodifiable(_surahs);

  @override
  Ayah? getAyah(int surah, int ayah) {
    final key = '$surah:$ayah';
    final text = _ayahs[key];
    if (text == null) return null;
    return Ayah(surahNumber: surah, ayahNumber: ayah, text: text);
  }

  @override
  List<Ayah> getSurahAyahs(int surah) {
    final result = <Ayah>[];
    for (final entry in _ayahs.entries) {
      final parts = entry.key.split(':');
      if (int.parse(parts[0]) == surah) {
        result.add(Ayah(
          surahNumber: surah,
          ayahNumber: int.parse(parts[1]),
          text: entry.value,
        ));
      }
    }
    return result;
  }

  @override
  List<String> searchText(String query, {bool normalized = true}) {
    // Simple contains for the stub.
    final hits = <String>[];
    for (final entry in _ayahs.entries) {
      if (entry.value.contains(query)) {
        hits.add(entry.key);
      }
    }
    return hits;
  }

  @override
  Future<void> initialize() async {
    _ready = true;
  }

  @override
  Future<void> dispose() async {
    _ready = false;
  }

  bool get isReady => _ready;
}
