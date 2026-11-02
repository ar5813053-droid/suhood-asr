# Suhood Al-Quran STT

**Offline-first Quranic Speech-to-Text engine for Android.**

Modular architecture designed for live Quran recitation transcription, Surah/Ayah identification, word-level tracking, multi-Qira'at support, and future Tajweed analysis.

> **Milestone 1 (Project Foundation) is complete.**  
> Speech recognition, real audio capture, and Quran matching are **not** implemented yet. The UI and interfaces are in place so development can continue safely without fake results.

---

## Vision

- Live transcription of Quran recitation on-device
- Automatic Surah and Ayah identification
- Word-level progress tracking
- Support for different Qira'at, Riwayat, reciters and regional pronunciation
- Future Tajweed analysis
- Fully offline-first (no mandatory network after model install)

Target device for early development: **POCO X3 Pro (6 GB RAM)**.  
Development is possible from an Android phone (Termux + browser + GitHub Actions).

---

## Current Status (Milestone 1)

| Component              | Status                          |
|------------------------|---------------------------------|
| Project structure      | ✅ Done                         |
| Flutter Android shell  | ✅ Done                         |
| Clean modular interfaces | ✅ Done                      |
| UI (Home + record button + placeholders) | ✅ Done |
| Stub engines (no fake data) | ✅ Done                  |
| Unit + widget tests    | ✅ Done                         |
| GitHub Actions debug APK | ✅ Configured                |
| Real microphone        | ❌ Not yet                      |
| Real ASR model         | ❌ Not yet                      |
| Real Quran database    | ❌ Stub (Al-Fatiha only)        |
| Surah/Ayah matcher     | ❌ Stub (always “no match”)     |

**Important engineering rules followed:**

- No pretended speech recognition
- No generated or hardcoded Quran transcripts
- No guessed Surah/Ayah results
- Audio, ASR and matching remain independent modules
- No large model downloads in this milestone
- Project stays lightweight

---

## Architecture

```
suhood-asr/
├── lib/
│   ├── main.dart                 # App entry
│   ├── state/app_state.dart      # UI + engine wiring
│   ├── ui/home_screen.dart       # Minimal professional UI
│   └── engine/
│       ├── audio/                # AudioSource interface + Stub
│       ├── asr/                  # AsrEngine interface + Stub
│       ├── quran/                # QuranTextProvider + Stub (Al-Fatiha)
│       ├── matcher/              # AyahMatcher interface + Stub
│       └── qiraat/               # QiraatSelector + known variants
├── test/                         # Unit & widget tests
├── android/                      # Native Android project
├── data/                         # Future model metadata & Quran DB
├── .github/workflows/            # CI that builds debug APK
└── README.md
```

### Module responsibilities

| Module            | Responsibility |
|-------------------|----------------|
| `engine/audio`    | Capture / stream PCM; independent of ASR |
| `engine/asr`      | Speech → text; never invents Quran text |
| `engine/quran`    | Canonical text + metadata access |
| `engine/matcher`  | Map ASR output → Surah:Ayah (conservative) |
| `engine/qiraat`   | Variant selection (Hafs first) |
| `app` / UI layer  | Presentation and state only |

All engines are defined behind clean Dart interfaces so implementations can be swapped later (e.g. Whisper, custom CTC, ONNX Runtime, etc.).

---

## UI (Milestone 1)

- Dark, minimal home screen
- Offline mode indicator (always on for now)
- Model status indicator (“Model: not loaded (M1)”)
- Detected Surah/Ayah placeholder (“—”)
- Live transcript placeholder that explicitly states ASR is not available
- Large Start / Stop recording button (UI + state only)

Tapping the button toggles recording state but does **not** produce transcripts or matches.

---

## Development Environment Notes

You are working primarily from an Android phone:

- **Termux** for git, shell and (later) local checks
- Browser for GitHub / Actions
- **GitHub Actions** for actual Android APK builds (no PC required)

### Building the APK via GitHub Actions

1. Push to `main` (or open a PR / run workflow manually)
2. Wait for the “Android Debug APK” workflow
3. Download the artifact named `suhood-asr-debug-apk`

The workflow:

- Checks out the repo
- Sets up Java 17 + Flutter 3.24 stable
- Runs `flutter pub get`, `flutter analyze`, `flutter test`
- Builds `flutter build apk --debug`
- Uploads the APK as a workflow artifact

---

## Local development (when a PC or full Flutter SDK is available)

```bash
flutter pub get
flutter analyze
flutter test
flutter run          # on connected device / emulator
flutter build apk --debug
```

---

## Roadmap (high level)

| Milestone | Focus |
|-----------|--------|
| **1**     | Foundation, interfaces, UI shell, CI (this release) |
| **2**     | Real microphone capture + audio pipeline |
| **3**     | First on-device ASR model (small, quantized) |
| **4**     | Full Quran text provider + basic matcher |
| **5**     | Streaming / live tracking + confidence gates |
| **6**     | Multi-Qira'at + pronunciation variants |
| **7+**    | Tajweed, word-level feedback, polish |

---

## Tests

```bash
flutter test
```

Coverage includes:

- All stub engines behave correctly and never invent data
- Home screen renders expected placeholders
- Record button toggles state

---

## License

MIT — see [LICENSE](LICENSE).

---

## Contributing / Next steps

This repository is the foundation. The next useful work is:

1. Wire a real `AudioSource` (Android AudioRecord or a Flutter plugin)
2. Integrate a small offline ASR model (keep size suitable for 6 GB devices)
3. Replace the Quran stub with a complete, authentic text source
4. Implement a conservative matcher that prefers “no match” over a wrong Ayah

PRs that add fake transcripts or hard-coded Surah results will be rejected.

---

*Built for the community that wants private, offline, accurate Quranic speech tools.*
