import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'state/app_state.dart';
import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Load native sherpa-onnx bindings once before any recognizer is created.
  try {
    sherpa_onnx.initBindings();
  } catch (_) {
    // On platforms without native libs (e.g. unit test host), continue;
    // ASR will surface an error when used.
  }
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const SuhoodApp());
}

class SuhoodApp extends StatelessWidget {
  const SuhoodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final state = AppState();
        state.initialize();
        return state;
      },
      child: MaterialApp(
        title: 'Suhood Al-Quran STT',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primaryColor: const Color(0xFF2D6A4F),
          scaffoldBackgroundColor: const Color(0xFF0F1419),
          fontFamily: 'Roboto',
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
