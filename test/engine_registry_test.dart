import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suhood_asr/engine/asr/engine_ids.dart';
import 'package:suhood_asr/engine/asr/engine_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('default is Zipformer primary', () {
    final r = EngineRegistry();
    expect(r.selectedId, kEngineZipformerQuran32);
    expect(r.isPrimarySelected, isTrue);
  });

  test('select diagnostic and persist', () async {
    final r = EngineRegistry();
    await r.select(kEngineQuranAsrSmall);
    expect(r.selectedId, kEngineQuranAsrSmall);
    expect(r.isDiagnosticSelected, isTrue);

    final r2 = EngineRegistry();
    await r2.load();
    expect(r2.selectedId, kEngineQuranAsrSmall);
  });

  test('select primary persists', () async {
    final r = EngineRegistry();
    await r.select(kEngineQuranAsrSmall);
    await r.select(kEngineZipformerQuran32);
    final r2 = EngineRegistry();
    await r2.load();
    expect(r2.selectedId, kEngineZipformerQuran32);
  });

  test('unknown engine throws', () async {
    final r = EngineRegistry();
    expect(() => r.select('nope'), throwsArgumentError);
  });

  test('display names', () {
    expect(engineDisplayName(kEngineZipformerQuran32), contains('Zipformer'));
    expect(engineDisplayName(kEngineQuranAsrSmall), contains('Diagnostic'));
  });
}
