# Rada — M0 walking skeleton

Personal Estonian 0→B1 companion (Android + macOS). See `estonian-b1-app-spec.md` for the full spec.

## What this skeleton contains

- `pubspec.yaml` — minimal M0 dependencies (Drift, Supabase, http)
- `lib/theme/` — token layer + two themes: **Vaikus** (calm default) and **Põhjavalgus** (dark aurora)
- `lib/data/db.dart` — Drift schema implementing spec §4 (courses, chapters, progress, activity log, vocab, sessions, exam plan…)
- `lib/data/seed_loader.dart` + `assets/seed/syllabus.json` — Keeleklikk (16 ch.) + Keeletee (13 ch.) syllabus seed
- `lib/services/` — service interfaces (TTS / STT / LLM / Sync) with M0-level implementations or stubs
- `lib/features/dashboard/` — placeholder dashboard: Trail progress strip, streak card, theme switcher, sync-test button

## Setup (on your Mac)

1. Install Flutter (stable): https://docs.flutter.dev/get-started/install/macos — enable macOS desktop + Android toolchains (`flutter doctor`).
2. Inside this folder, generate the platform folders (they are deliberately not committed):

   ```bash
   cp .env.example .env          # required even if left empty (bundled as asset)
   flutter create --platforms=android,macos --project-name rada .
   flutter pub get
   dart run build_runner build   # generates db.g.dart for Drift
   ```

3. Run it:

   ```bash
   flutter run -d macos     # or -d <android-device-id>
   ```

## M0 acceptance: sync a dummy record Mac ↔ phone

1. Create a free project at https://supabase.com.
2. In the SQL editor, run `supabase/schema.sql`.
3. Copy `.env.example` → `.env`, fill `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
4. Launch on both devices, press **"Sync test"** on the dashboard — a `sync_probe` row written on one device should appear on the other.

## Next (M1)

Webview course embed + chapter checklist, real Trail home screen, quest card, streaks from activity_log, exam countdown. See spec §11.
