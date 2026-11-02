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
          // Do not await initialize in test to keep it synchronous.
          return state;
        },
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    expect(find.text('Suhood Al-Quran STT'), findsOneWidget);
    expect(find.textContaining('Model:'), findsOneWidget);
    expect(find.text('Detected location'), findsOneWidget);
    expect(find.text('Live transcript'), findsOneWidget);
    expect(find.text('Tap to start'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);
  });

  testWidgets('Toggling record updates button label', (tester) async {
    final state = AppState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    expect(find.text('Tap to start'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.mic));
    await tester.pump();
    expect(find.text('Tap to stop'), findsOneWidget);
    expect(state.isRecording, isTrue);

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();
    expect(find.text('Tap to start'), findsOneWidget);
    expect(state.isRecording, isFalse);
  });
}
