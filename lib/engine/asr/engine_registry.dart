/// Explicit ASR engine selection. No automatic fallback.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'engine_ids.dart';

const _prefsKey = 'suhood_selected_engine_id';

class EngineRegistry {
  String _selectedId = kDefaultEngineId;

  String get selectedId => _selectedId;

  bool get isPrimarySelected => _selectedId == kEngineZipformerQuran32;
  bool get isDiagnosticSelected => _selectedId == kEngineQuranAsrSmall;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored == kEngineZipformerQuran32 || stored == kEngineQuranAsrSmall) {
      _selectedId = stored!;
    } else {
      _selectedId = kDefaultEngineId;
    }
  }

  /// Persist explicit user choice. Caller must stop recording and dispose
  /// the previous engine before switching.
  Future<void> select(String engineId) async {
    if (engineId != kEngineZipformerQuran32 &&
        engineId != kEngineQuranAsrSmall) {
      throw ArgumentError('Unknown engine id: $engineId');
    }
    _selectedId = engineId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, engineId);
  }
}
