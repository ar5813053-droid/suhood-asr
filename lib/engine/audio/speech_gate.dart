/// Adaptive speech / silence gate for the Quran ASR pipeline.
///
/// Purpose: never send pure silence or ambient noise to the CTC model,
/// which otherwise hallucinates Arabic letters on quiet input.
///
/// This is NOT a neural VAD. It combines:
/// - adaptive noise-floor estimation (EMA of low-energy frames)
/// - RMS energy relative to the noise floor
/// - peak amplitude check
/// - hangover (keep-alive after speech) so short pauses mid-ayah
///   do not fragment the segment
/// - minimum speech duration before a segment is considered "speech"
///
/// Silero neural VAD can be layered on top later; this gate alone
/// already blocks the false-transcript failure mode.
library;

import 'dart:math' as math;

import 'audio_source.dart';

enum SpeechState {
  silence,
  speech,
  hangover, // recent speech, pause in progress
}

class SpeechGateConfig {
  /// Absolute RMS below which a frame is treated as near-silence (float scale).
  final double absoluteSilenceRms;

  /// Peak |sample|/32768 below which frame is noise.
  final double minPeak;

  /// How many times above noise floor counts as speech.
  final double speechOverNoiseRatio;

  /// EMA alpha for noise-floor tracking (0..1, lower = slower).
  final double noiseEmaAlpha;

  /// Frames of hangover after speech ends (each frame ~20–30 ms of analysis).
  final int hangoverFrames;

  /// Minimum consecutive speech frames to open a speech segment.
  final int minSpeechFrames;

  /// Analysis window size in samples (16 kHz → 320 = 20 ms).
  final int frameSamples;

  const SpeechGateConfig({
    this.absoluteSilenceRms = 0.008,
    this.minPeak = 0.02,
    this.speechOverNoiseRatio = 2.5,
    this.noiseEmaAlpha = 0.05,
    this.hangoverFrames = 25, // ~500 ms
    this.minSpeechFrames = 8, // ~160 ms
    this.frameSamples = 320,
  });
}

class FrameStats {
  final double rms;
  final double peak;
  final bool isSpeechLike;

  const FrameStats({
    required this.rms,
    required this.peak,
    required this.isSpeechLike,
  });
}

class SpeechGate {
  SpeechGate({SpeechGateConfig? config}) : config = config ?? const SpeechGateConfig();

  final SpeechGateConfig config;

  double noiseFloor = 0.01;
  SpeechState state = SpeechState.silence;
  int _speechRun = 0;
  int _hangoverLeft = 0;

  // Debug counters
  int framesSeen = 0;
  int framesSpeech = 0;
  int segmentsAccepted = 0;
  int segmentsRejected = 0;

  void reset() {
    noiseFloor = 0.01;
    state = SpeechState.silence;
    _speechRun = 0;
    _hangoverLeft = 0;
  }

  FrameStats analyzeFrame(List<int> pcm16) {
    if (pcm16.isEmpty) {
      return const FrameStats(rms: 0, peak: 0, isSpeechLike: false);
    }
    var sumSq = 0.0;
    var peak = 0.0;
    for (final s in pcm16) {
      final v = s / 32768.0;
      sumSq += v * v;
      final a = v.abs();
      if (a > peak) peak = a;
    }
    final rms = math.sqrt(sumSq / pcm16.length);

    // Update noise floor only on quiet frames
    final quiet = rms < noiseFloor * 1.5 || rms < config.absoluteSilenceRms * 2;
    if (quiet) {
      noiseFloor =
          (1 - config.noiseEmaAlpha) * noiseFloor + config.noiseEmaAlpha * rms;
      // Keep a floor so ratio stays stable
      if (noiseFloor < 0.001) noiseFloor = 0.001;
    }

    final overNoise = rms > noiseFloor * config.speechOverNoiseRatio;
    final loudEnough =
        rms >= config.absoluteSilenceRms && peak >= config.minPeak;
    final speechLike = overNoise && loudEnough;

    framesSeen++;
    if (speechLike) framesSpeech++;

    return FrameStats(rms: rms, peak: peak, isSpeechLike: speechLike);
  }

  /// Feed continuous PCM; updates internal VAD state.
  void processSamples(List<int> pcm16) {
    final n = config.frameSamples;
    for (var i = 0; i + n <= pcm16.length; i += n) {
      final frame = pcm16.sublist(i, i + n);
      final stats = analyzeFrame(frame);
      _updateState(stats.isSpeechLike);
    }
    // leftover samples ignored until next call (accumulate externally if needed)
  }

  void _updateState(bool speechLike) {
    switch (state) {
      case SpeechState.silence:
        if (speechLike) {
          _speechRun++;
          if (_speechRun >= config.minSpeechFrames) {
            state = SpeechState.speech;
            _speechRun = 0;
          }
        } else {
          _speechRun = 0;
        }
        break;
      case SpeechState.speech:
        if (speechLike) {
          _hangoverLeft = config.hangoverFrames;
        } else {
          _hangoverLeft = config.hangoverFrames;
          state = SpeechState.hangover;
        }
        break;
      case SpeechState.hangover:
        if (speechLike) {
          state = SpeechState.speech;
          _hangoverLeft = config.hangoverFrames;
        } else {
          _hangoverLeft--;
          if (_hangoverLeft <= 0) {
            state = SpeechState.silence;
          }
        }
        break;
    }
  }

  bool get inSpeechRegion =>
      state == SpeechState.speech || state == SpeechState.hangover;

  /// Whether a buffered segment should be sent to ASR.
  bool shouldRecognizeSegment(List<int> pcm16, {required bool finalFlush}) {
    if (pcm16.isEmpty) {
      segmentsRejected++;
      return false;
    }
    // Minimum duration ~0.4 s
    if (pcm16.length < 6400) {
      segmentsRejected++;
      return false;
    }

    // Walk frames and count speech-like frames in this segment only
    // (does not depend solely on streaming state, so silent buffers fail)
    final n = config.frameSamples;
    var speechFrames = 0;
    var totalFrames = 0;
    var maxRms = 0.0;
    for (var i = 0; i + n <= pcm16.length; i += n) {
      final st = analyzeFrame(pcm16.sublist(i, i + n));
      totalFrames++;
      if (st.isSpeechLike) speechFrames++;
      if (st.rms > maxRms) maxRms = st.rms;
    }

    // Require meaningful speech fraction
    final minSpeechFraction = finalFlush ? 0.08 : 0.12;
    final minSpeechFramesAbs = finalFlush ? 5 : 10;
    final ok = totalFrames > 0 &&
        speechFrames >= minSpeechFramesAbs &&
        (speechFrames / totalFrames) >= minSpeechFraction &&
        maxRms >= config.absoluteSilenceRms;

    if (ok) {
      segmentsAccepted++;
    } else {
      segmentsRejected++;
    }
    return ok;
  }
}

/// DC offset removal (simple mean subtraction). Does not change speech content.
List<int> removeDcOffset(List<int> samples) {
  if (samples.isEmpty) return samples;
  var sum = 0;
  for (final s in samples) {
    sum += s;
  }
  final mean = sum ~/ samples.length;
  if (mean.abs() < 2) return samples;
  return samples.map((s) => (s - mean).clamp(-32768, 32767)).toList();
}

/// Validate PCM for ASR: non-empty, mono 16 kHz expectation, not all zeros.
bool isValidPcmForAsr(AudioChunk chunk, {int minSamples = 1600}) {
  if (chunk.sampleRate != 16000) return false;
  if (chunk.channels != 1) return false;
  if (chunk.samples.length < minSamples) return false;
  // Reject all-zero / near-zero buffers
  var any = false;
  for (final s in chunk.samples) {
    if (s.abs() > 8) {
      any = true;
      break;
    }
  }
  return any;
}
