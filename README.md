# Suhood Al-Quran STT

**Offline-first Quranic Speech-to-Text engine for Android.**

Modular architecture for live Quran recitation transcription, Surah/Ayah identification, word-level tracking, multi-Qira'at support, and future Tajweed analysis.

> **Milestone 2 is implemented:** real microphone capture + offline Quran ASR baseline (`Abdou/quran-asr-small` via sherpa-onnx).

---

## Vision

- Live transcription of Quran recitation on-device
- Automatic Surah and Ayah identification
- Word-level progress tracking
- Support for different Qira'at, Riwayat, reciters and regional pronunciation
- Future Tajweed analysis
- Fully offline-first after model install

Target device: **POCO X3 Pro (6 GB RAM)**.  
Development is possible from an Android phone (Termux + browser + GitHub Actions).

---

## Current Status (Milestone 2)

| Component | Status |
|-----------|--------|
| Project structure | ✅ |
| Flutter Android shell | ✅ |
| Modular interfaces | ✅ |
| Real microphone capture (16 kHz mono PCM) | ✅ |
| Permission handling | ✅ |
| Audio level metering | ✅ |
| Model download (runtime, not in git) | ✅ |
| Offline Quran ASR (quran-asr-small int8) | ✅ |
| Chunk / segment transcription | ✅ |
| UI: download, level, transcript, clear | ✅ |
| Surah/Ayah matcher | ❌ Stub (always no match) |
| True frame-level streaming ASR | ❌ Segment-based offline CTC |

**Honest behaviour:** The model is offline Zipformer/Conformer CTC. The app records continuously and runs recognition on ~3 s segments with overlap. This is **not** claimed as true streaming inference.

---

## ASR model

| Field | Value |
|-------|--------|
| Model | [Abdou/quran-asr-small](https://huggingface.co/Abdou/quran-asr-small) |
| Size | ~36 MB int8 ONNX |
| License | MIT |
| Runtime | sherpa-onnx (Flutter) |
| Sample rate | 16 kHz mono |
| Benchmark | ~4.49% WER / 2.17% CER (Quran-Lab) |

Model files are **downloaded on first use** into app support storage. They are **not** committed to this repository.

---

## Architecture

```
lib/
  engine/
    audio/     MicAudioSource (real) + Stub
    asr/       SherpaQuranAsrEngine + ModelManager + interfaces
    quran/     text provider (stub Al-Fatiha)
    matcher/   ayah matcher (stub)
    qiraat/    variant selector
  state/       AppState (recording + transcription pipeline)
  ui/          HomeScreen
```

---

## Usage on device

1. Install the debug APK from GitHub Actions.
2. Open the app → tap **Download model** (one-time, ≈36 MB, needs network once).
3. Grant microphone permission.
4. Tap the mic button and recite.
5. Transcription appears in Arabic (Uthmani letters as produced by the model).
6. After download, recognition works fully offline.

---

## Build (GitHub Actions)

Push to `main` runs:

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build apk --debug`
- Uploads artifact `suhood-asr-debug-apk`

---

## Local development

```bash
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --debug
```

---

## Roadmap

| Milestone | Focus |
|-----------|--------|
| **1** | Foundation, interfaces, UI shell, CI |
| **2** | Real mic + offline Quran ASR baseline (this release) |
| **3** | Improved segmentation / VAD, latency measurement |
| **4** | Full Quran text + conservative matcher |
| **5** | Live tracking + confidence gates |
| **6** | Multi-Qira'at |
| **7+** | Tajweed, polish |

---

## License

MIT — see [LICENSE](LICENSE).  
The ASR model is MIT; training data retains its own terms (see model card).

---

*Built for private, offline, accurate Quranic speech tools.*
