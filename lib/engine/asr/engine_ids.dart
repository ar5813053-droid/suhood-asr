/// Stable engine identifiers for Suhood ASR.
///
/// Selection is always explicit. There is no automatic fallback between engines.
library;

/// Primary engine: Quran-Lab Zipformer Quran 3.2 (streaming phoneme CTC).
const String kEngineZipformerQuran32 = 'zipformer_quran_3_2';

/// Optional diagnostic engine: Abdou/quran-asr-small (offline text CTC).
const String kEngineQuranAsrSmall = 'quran_asr_small';

const String kDefaultEngineId = kEngineZipformerQuran32;

/// Human-readable labels for UI.
String engineDisplayName(String id) {
  switch (id) {
    case kEngineZipformerQuran32:
      return 'Zipformer Quran 3.2';
    case kEngineQuranAsrSmall:
      return 'Diagnostic — quran-asr-small';
    default:
      return id;
  }
}

String engineSubtitle(String id) {
  switch (id) {
    case kEngineZipformerQuran32:
      return 'Primary · streaming phoneme recognition';
    case kEngineQuranAsrSmall:
      return 'Optional · offline text CTC (diagnostic only)';
    default:
      return '';
  }
}
