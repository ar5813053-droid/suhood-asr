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
              // Model status + download
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onLongPress: () =>
                                  state.setDebugMode(!state.debugMode),
                              child: Icon(
                                Icons.memory,
                                size: 18,
                                color: state.asrStatus == AsrModelStatus.ready
                                    ? const Color(0xFF95D5B2)
                                    : const Color(0xFF8B949E),
                              ),
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
                            if (!state.modelReady && !state.isDownloading)
                              TextButton(
                                onPressed: () => state.downloadAndLoadModel(),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF95D5B2),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Download model',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                        if (state.isDownloading) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: state.downloadProgress > 0
                                ? state.downloadProgress
                                : null,
                            backgroundColor: const Color(0xFF2A3544),
                            color: const Color(0xFF2D6A4F),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // Audio level
              Consumer<AppState>(
                builder: (context, state, _) {
                  return Row(
                    children: [
                      Icon(
                        state.isRecording ? Icons.mic : Icons.mic_off,
                        size: 16,
                        color: state.isRecording
                            ? const Color(0xFF95D5B2)
                            : const Color(0xFF8B949E),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: state.audioLevel,
                            minHeight: 6,
                            backgroundColor: const Color(0xFF2A3544),
                            color: const Color(0xFF40916C),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        state.isRecording ? state.listenStatus : 'Idle',
                        style: const TextStyle(
                          color: Color(0xFF8B949E),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  );
                },
              ),
              // Debug metrics (only when enabled via long-press on model status later)
              Consumer<AppState>(
                builder: (context, state, _) {
                  if (!state.debugMode) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'VAD: ${state.vadStateLabel}  floor: ${state.noiseFloor.toStringAsFixed(4)}  '
                      'rms: ${state.audioLevel.toStringAsFixed(3)}  peak: ${state.peakLevel.toStringAsFixed(3)}\n'
                      'ASR calls: ${state.asrCalls}  ok: ${state.asrAccepted}  rej: ${state.asrRejected}  '
                      '${state.lastInferenceMs} ms\n'
                      'reject: ${state.lastRejectReason}\n'
                      'merge: ${state.lastMergeNote}\n'
                      'raw: ${state.lastRawAsr}\n'
                      'filtered: ${state.lastFilteredAsr}\n'
                      'CTC confidence: not available in current runtime',
                      style: const TextStyle(color: Color(0xFF6E7681), fontSize: 10),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Detected location (still placeholder for matcher)
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
              const SizedBox(height: 16),

              // Transcript
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Transcription',
                    style: TextStyle(
                      color: Color(0xFF8B949E),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Consumer<AppState>(
                    builder: (context, state, _) {
                      return TextButton(
                        onPressed: state.clearTranscript,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF8B949E),
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Clear',
                          style: TextStyle(fontSize: 12),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Consumer<AppState>(
                  builder: (context, state, _) {
                    final text = state.transcriptDisplay;
                    final placeholder = !state.modelReady
                        ? 'Download the model (≈36 MB, one-time),\nthen start recording to transcribe Quran recitation.\n\nOffline after download.'
                        : (state.isRecording
                            ? 'Listening… speak a verse'
                            : 'Press the microphone to begin.');
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
                          text.isEmpty ? placeholder : text,
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: text.isEmpty
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

              // Error
              Consumer<AppState>(
                builder: (context, state, _) {
                  if (state.errorMessage == null) {
                    return const SizedBox(height: 8);
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      state.errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFE07A5F),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

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
