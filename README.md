# Rada — Estonian 0→B1 companion

Personal study app (Android + macOS). Spec: `docs/estonian-b1-app-spec.md`. Review/backlog: `docs/REVIEW-2026-11.md`.

## Install

Builds are produced by CI and published to git branches:
`dist-macos` → `Rada.dmg` · `dist-android` → `rada.apk`.

- macOS: open the .dmg, drag to Applications. Unsigned → first launch: right-click → Open.
- Android: sideload the .apk (allow unknown sources).

## In-app setup (no build-time config)

Everything the app needs is entered in-app — there is no `.env`:

- **Settings (gear)** → Supabase URL + publishable key for sync (create a free project, run `supabase/schema.sql` in its SQL editor first). Theme, daily goal, app language, exam date.
- **Speech studio → voice settings** → Anthropic API key + model (cloud) or LM Studio URL (local), Whisper server URL, TTS voice.

### Whisper server (pronunciation / voice input)

```bash
brew install whisper-cpp
whisper-server -m <model.bin> --port 8090 --language et
```

Start with the multilingual `large-v3-turbo` model; TalTech's Estonian fine-tune (`TalTechNLP/whisper-large-et`) is the upgrade once converted to GGML.

## Developing locally

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d macos   # or an Android device
```

Native folders (`android/`, `macos/`) are committed. Android release builds are signed with the committed dev keystore (`android/app/rada-dev.jks`, see `android/key.properties`) so updates install over previous versions — this is a personal app; never reuse that key for anything distributed.

## CI

- Every push: `flutter analyze` + tests (Linux). Log published to `ci-logs` branch.
- Push to `main` or manual dispatch: macOS .dmg and Android .apk → `dist-*` branches.
