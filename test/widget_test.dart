import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:suhood_asr/state/app_state.dart';
import 'package:suhood_asr/ui/home_screen.dart';

void main() {
  testWidgets('Home screen shows core placeholders', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) {
          final state = AppState();
          return state;
        },
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    expect(find.text('Suhood Al-Quran STT'), findsOneWidget);
    expect(find.textContaining('Model:'), findsOneWidget);
    expect(find.text('Detected location'), findsOneWidget);
    expect(find.text('Transcription'), findsOneWidget);
    expect(find.text('Tap to start'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);
  });

  testWidgets('Clear button is present', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    expect(find.text('Clear'), findsOneWidget);
  });
}
