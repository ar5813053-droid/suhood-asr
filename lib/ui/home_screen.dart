import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/asr/asr_engine.dart';
import '../state/app_state.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1419),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A2332),
        elevation: 0,
        title: const Text(
          'Suhood Al-Quran STT',
          style: TextStyle(
            color: Color(0xFFE8E6E3),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          Consumer<AppState>(
            builder: (context, state, _) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Chip(
                  backgroundColor: state.offlineMode
                      ? const Color(0xFF1B4332)
                      : const Color(0xFF3D2C1E),
                  label: Text(
                    state.offlineMode ? 'Offline' : 'Online',
                    style: TextStyle(
                      color: state.offlineMode
                          ? const Color(0xFF95D5B2)
                          : const Color(0xFFE9C46A),
                      fontSize: 12,
                    ),
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Model status
              Consumer<AppState>(
                builder: (context, state, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2332),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2A3544)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.memory,
                          size: 18,
                          color: state.asrStatus == AsrModelStatus.ready
                              ? const Color(0xFF95D5B2)
                              : const Color(0xFF8B949E),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            state.modelStatusLabel,
                            style: const TextStyle(
                              color: Color(0xFFC9D1D9),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // Detected Surah / Ayah placeholder
              const Text(
                'Detected location',
                style: TextStyle(
                  color: Color(0xFF8B949E),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Consumer<AppState>(
                builder: (context, state, _) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2332),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2A3544)),
                    ),
                    child: Text(
                      state.detectedSurahAyah,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFE8E6E3),
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // Live transcript placeholder
              const Text(
                'Live transcript',
                style: TextStyle(
                  color: Color(0xFF8B949E),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Consumer<AppState>(
                  builder: (context, state, _) {
                    final text = state.liveTranscript.isEmpty
                        ? (state.isRecording
                            ? 'Listening… (ASR not yet available)'
                            : 'Press the microphone to begin.\n\nNo speech recognition is active in Milestone 1.')
                        : state.liveTranscript;
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2332),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2A3544)),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          text,
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: state.liveTranscript.isEmpty
                                ? const Color(0xFF6E7681)
                                : const Color(0xFFE8E6E3),
                            fontSize: 18,
                            height: 1.6,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),

              // Record button
              Consumer<AppState>(
                builder: (context, state, _) {
                  return Center(
                    child: GestureDetector(
                      onTap: () => state.toggleRecording(),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: state.isRecording
                              ? const Color(0xFF9B2226)
                              : const Color(0xFF2D6A4F),
                          boxShadow: [
                            BoxShadow(
                              color: (state.isRecording
                                      ? const Color(0xFF9B2226)
                                      : const Color(0xFF2D6A4F))
                                  .withOpacity(0.4),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          state.isRecording ? Icons.stop_rounded : Icons.mic,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Consumer<AppState>(
                builder: (context, state, _) {
                  return Text(
                    state.isRecording ? 'Tap to stop' : 'Tap to start',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF8B949E),
                      fontSize: 13,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
