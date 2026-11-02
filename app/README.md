# Application layer

The Flutter application lives at the repository root (standard Flutter layout) so that `flutter build apk` and GitHub Actions work without extra path configuration.

UI code: `lib/ui/`
State & wiring: `lib/state/`
Entry point: `lib/main.dart`

Engine modules are under `lib/engine/` and remain independent of the UI.
