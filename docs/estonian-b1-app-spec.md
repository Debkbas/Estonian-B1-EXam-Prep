# Rada — Estonian 0→B1 Companion App
**Technical Specification v1.0 — July 2026**
*(Working name "Rada" — Estonian for "trail/path". Rename freely.)*

---

## 1. Purpose & success criteria

A personal two-app system (Android + macOS, synced) that carries one learner (English speaker) from zero Estonian to passing the official **eesti keele B1-taseme eksam**.

**Success criteria**

1. Pass the B1 exam: ≥60% overall, no section at 0. Sections: kirjutamine (writing), kuulamine (listening), lugemine (reading), rääkimine (speaking) — 25 pts each.
2. Sustained daily engagement: the motivation layer (streaks, visible progress, exam countdown) keeps a daily habit alive without willpower heroics.
3. Everything needed lives in one place: courses, exam materials, speech practice, vocab review.

**Non-goals:** multi-user support, app-store distribution, monetization, replicating course content authoring. Personal project.

**Target exam dates (verified July 2026, harno.ee):**
- **6 Sept 2026** — register by 1 Aug 2026 (likely too soon)
- **8 Nov 2026** — register by 1 Oct 2026
- Quarterly thereafter (Tallinn, Tartu, Narva, Jõhvi, sometimes Pärnu). Registration via EIS: https://eis.harno.ee/
- Free pre-exam consultation (attendable without exam registration); B1 consultations ~2–3 weeks before each exam.
- Rule to encode: if score <45% or no-show, 6-month retake lockout → don't register until mock exams say ready.

---

## 2. Product shape

| | **macOS app — "the Studio"** | **Android app — "the Companion"** |
|---|---|---|
| Role | Full practice environment | On-the-go tracker + light practice |
| Course access | Embedded webview + offline mirror (§5) | Embedded webview / external browser |
| Progress/streaks/checklists | ✅ | ✅ |
| Exam material vault | ✅ full (PDF viewer, audio player, mock exams) | ✅ read/listen |
| Speech tutor (STT + TTS + LLM) | ✅ fully local option | v2: via Mac hub (LAN) or cloud |
| Vocab SRS review | ✅ | ✅ (primary home — phone moments) |
| Sync | Supabase (offline-first) | Supabase (offline-first) |

One Flutter codebase, two targets. The Mac is the heavyweight node; the phone never blocks on it for tracker/vocab/exam-vault features.

---

## 3. Architecture

```
┌─────────────────────────── Flutter app (Dart) ───────────────────────────┐
│  UI layer (Material 3, adaptive desktop/mobile layouts)                  │
│  ├── Dashboard (streak, progress %, exam countdown, "what's next")       │
│  ├── Course module (webview embed + chapter checklist overlay)           │
│  ├── Exam vault (PDF viewer, audio player, mock-exam runner)             │
│  ├── Speech studio (drills, conversation, writing feedback)              │
│  └── Vocab SRS (flashcards, FSRS scheduling)                             │
│                                                                          │
│  Domain layer (pure Dart) — entities §4, SRS scheduler, scoring,         │
│                             streak rules, mock-exam grading              │
│                                                                          │
│  Service layer (interfaces + per-platform implementations)               │
│  ├── TtsService      → Neurokõne REST API (all platforms, cached audio)  │
│  ├── SttService      → macOS: whisper.cpp FFI (whisper-large-et GGML)    │
│  │                     Android: HubClient → Mac over LAN, or cloud       │
│  ├── LlmService      → OpenAI-compatible adapter:                        │
│  │                     • local: LM Studio endpoint (http://mac:1234/v1)  │
│  │                     • cloud: Anthropic API                            │
│  │                     Runtime-switchable per feature (hybrid)           │
│  ├── SyncService     → Supabase (Postgres + auth), offline queue, LWW    │
│  ├── ArchiveService  → offline course mirror (§5.2), localhost server    │
│  └── AssetService    → bundled Harno PDFs/MP3s, download manager         │
│                                                                          │
│  Storage: Drift (SQLite) local-first DB; Supabase mirrors it for sync    │
└──────────────────────────────────────────────────────────────────────────┘

External: keeleklikk.ee · keeletee.edu.ee · harno.ee assets ·
          api.tartunlp.ai (Neurokõne TTS) · Supabase · LM Studio · Claude API
```

**Key decisions**

- **Flutter over KMP/PWA** — one codebase, first-class macOS desktop + Android, FFI for whisper.cpp, mature webview/audio plugins. PWA can't run local Whisper; Compose-for-macOS is immature.
- **Local-first, sync-second.** SQLite (Drift) is the source of truth on each device; Supabase is the courier. The app is fully usable offline; sync is background reconciliation.
- **Hybrid LLM by design, not fallback.** `LlmService` is one interface with two adapters. A settings screen picks local (LM Studio, OpenAI-compatible) or cloud (Claude API) *per feature* — e.g. cloud for grammar correction (quality-critical), local for casual conversation practice. Both configurable endpoints, keys stored in platform keychain.
- **Speech is Mac-first.** Android speech lands in a later milestone via "hub mode" (phone records → Mac transcribes/responds over LAN) or direct cloud. Never a v1 blocker.

---

## 4. Data model

All tables carry `id (uuid)`, `created_at`, `updated_at`, `device_id`, `deleted (bool)` for sync. Conflict resolution: last-write-wins per row on `updated_at` (single user, two devices — LWW is sufficient; streaks are recomputed from `activity_log`, never merged).

### 4.1 Syllabus & progress

```
course        slug ('keeleklikk'|'keeletee'), title, level_range,
              chapters_total (16 / 13), base_url, teacher_email
chapter       course_id, index (1..n), title_et, title_en, url_fragment,
              est_minutes  -- rough effort estimate for planning
chapter_item  chapter_id, kind ('lesson'|'exercise_block'|'grammar_video'|
              'chapter_test'), label, ord
              -- granularity knob: v1 may track only whole chapters;
              -- schema allows finer ticks later without migration
progress      target_type ('chapter'|'chapter_item'), target_id,
              status ('todo'|'doing'|'done'), completed_at, self_score, note
```

Syllabus content ships as a seed JSON (curated by hand once from the course tables of contents) — the app never depends on scraping to know the syllabus.

### 4.2 Motivation

```
activity_log  date, minutes, kind ('course'|'vocab'|'speech'|'exam_prep'|
              'writing'), detail_json
daily_goal    minutes_target (default 25), days_per_week (default 6)
streak        -- DERIVED, never stored authoritative:
              current = consecutive days meeting goal (1 grace day/week)
exam_plan     exam_date, registration_deadline, consultation_date,
              registered (bool), location
              -- drives countdown + phase switching (§7)
```

### 4.3 Vocabulary (SRS)

```
vocab_item    et, en, example_et, example_en, audio_cache_path,
              source ('keeleklikk ch.4'|'exam task'|'conversation'|manual),
              fsrs_due, fsrs_stability, fsrs_difficulty, fsrs_state
review_log    vocab_item_id, reviewed_at, rating (again/hard/good/easy)
```

FSRS algorithm (open, well-documented, better than SM-2). Speech studio and writing feedback can push new items ("you didn't know *ometi* — added to deck").

### 4.4 Practice & exam prep

```
practice_session  mode ('listen'|'pronounce'|'converse'|'write'|'mock_exam'),
                  started_at, duration_s, llm_backend ('local'|'cloud'|null),
                  payload_json  -- mode-specific: target text, transcript,
                                -- alignment score, LLM feedback, essay text
exam_asset        kind ('pdf'|'mp3'|'link'), section ('kirjutamine'|'kuulamine'|
                  'lugemine'|'rääkimine'|'general'), title, remote_url,
                  local_path, sha256
mock_exam         started_at, sections_json (per-section raw + % scores),
                  total_pct, notes
answer_key        exam_asset_id, task_ref, answers_json
                  -- hand-entered once per sample task; enables auto-grading
                  -- of reading/listening mocks
```

---

## 5. Course integration

### 5.1 Primary: webview embed + checklist overlay

- Course opens inside the app (`webview_flutter` on Android, `webview_flutter` / native WKWebView wrapper on macOS), session cookies persisted so login survives restarts.
- A slim sidebar/overlay shows the chapter checklist; the learner ticks off chapters/items manually (courses expose no progress API — accepted).
- "Continue where I left off" deep-links to the last chapter's `url_fragment`.
- Teacher email support is preserved (mailto links per course).

### 5.2 Hybrid exploration: personal offline mirror (ArchiveService)

**Status: exploratory spike, timeboxed (M4). Personal use only — never redistributed. Webview remains the primary path regardless of outcome.**

Approach, in increasing order of effort — stop at the first level that works:

1. **Media-only harvest.** Crawl chapter pages with Playwright (logged in with the learner's own account), collect video/audio/animation URLs, download into `archive/{course}/{chapter}/media/`. App gets an offline "watch/listen" list per chapter. Highest value-to-effort: grammar videos and dialogue audio are the assets you actually revisit.
2. **Full static mirror.** Playwright crawl saving rendered DOM + assets; serve via an embedded localhost HTTP server (`shelf`); webview pointed at `http://127.0.0.1:<port>/...` when offline. Risk: exercise engine likely calls server-side endpoints (answer checking, teacher messaging) → interactive exercises may render but not function.
3. **Exercise re-implementation.** Extract exercise text/answers from the DOM and re-host in native Flutter widgets. Only if (2) shows exercises are data-driven and extraction is clean. Do not commit to this blind — it can eat the whole project.

**Spike protocol (1–2 days, hard stop):** archive Keeleklikk chapter 1 only → test offline → write down what works (videos? audio? exercises? navigation?) → decide level 1/2/3 or "webview only" based on evidence.

**Legal note:** state-funded, free-to-access, but not open-licensed. A personal archive for own study is the same class of act as saving pages for offline reading — low risk. Redistribution would not be. The app ships with the archive *empty*; the ArchiveService fills it on the user's machine with the user's account.

### 5.3 Course path (seeded)

Keeleklikk ch. 1–16 (0→A2) → Keeletee ch. 1–13 (A2→B1) → exam-prep phase. The B2 Keeleklikk (in development through 2026) can be appended later as `course` row #3.

---

## 6. Speech-tutor pipeline

### 6.1 TTS — "the app speaks Estonian"

- **Engine:** Neurokõne (TartuNLP) public REST API — free, 10 voices, quality far above anything local-generic.
- Every synthesized utterance cached to disk keyed by `sha256(voice+text)` — repeat listening costs zero calls and works offline afterwards.
- Speed control ("öelge aeglasemalt") via API rate parameter; every Estonian string in the UI (vocab items, examiner questions, corrections) gets a speaker icon.
- Android on-device TTS later, using TartuNLP's open-source `neurokone_app` as reference (license check first). Not on the critical path — API + cache covers 95% of use.

### 6.2 STT — "the app hears you"

- **macOS:** `whisper-large-et` (TalTech, ~1,200 h Estonian fine-tune) converted to GGML, run through whisper.cpp via Dart FFI. Fallback if conversion misbehaves: `whisper-medium-et`, or a tiny localhost Python sidecar running faster-whisper (decide in M3, prefer FFI).
- **Android (M5):** record locally → POST to the Mac ("hub mode", mDNS discovery on LAN) → or cloud STT if away from home. Phone never runs Whisper.

### 6.3 Pronunciation / read-aloud drill

```
target sentence → learner reads aloud → whisper-large-et transcript
→ normalize (lowercase, strip punctuation) → word-level alignment
  (Levenshtein) → per-word match/miss highlighting → score %
```

Honest framing in UI: this checks *"was your Estonian intelligible enough for a good Estonian ASR to understand"* — a strong proxy for exam intelligibility, not phoneme-level coaching. Miss patterns (e.g. persistent õ/ö confusion) surface as stats over time.

### 6.4 Conversation & correction (LLM, hybrid)

- **Modes:** free conversation at B1-constrained vocabulary; scenario drills (shop, doctor, work — the exam's topic circles); **exam simulation** of rääkimine tasks: examiner intro questions, then the two official task formats (opinion questions + information-exchange dialogue), timed 6–7 and 4–5 min.
- **Loop:** learner speaks → STT → LLM replies *in Estonian at B1 level* + separate structured correction block `{original, corrected, error_type, one-line explanation in English}` → TTS speaks the reply. Corrections accumulate into a per-session report; recurring errors become SRS cards.
- **Backend policy (settings, per-feature):** default **cloud (Claude) for corrections and writing feedback** — local models' Estonian grammar is unreliable and confident-but-wrong feedback is worse than none. Local (LM Studio) allowed for conversation *flow* and offline practice; UI labels local-generated corrections as "unverified".

### 6.5 Writing feedback (kirjutamine)

- Task templates mirror the exam: **personal letter** and short message formats, with word-count targets from official specs.
- Learner writes in-app → LLM grades against a rubric derived from the official B1 assessment criteria (task completion, vocabulary range, grammar, coherence) → inline corrections + model answer comparison (official sooritusnäidis bundled for calibration).
- Every submission stored in `practice_session` — progress over months is visible.

---

## 7. Exam-prep module

**Bundled assets (verified URLs, July 2026)** — downloaded once by AssetService, stored locally, checksummed:

- B1 konsultatsioonivihik (workbook) + fillable version — harno.ee PDFs
- B1 sample tasks per section: writing (isiklik kiri), listening tasks 1–4 + MP3s, reading tasks 1–4, speaking task sheets — harno.ee / projektid.edu.ee
- B1 kuulamistest full MP3; B1-taseme sooritusnäidis (graded performance sample)
- Reference book: „Iseseisev keelekasutaja. B1- ja B2-taseme eesti keele oskus" (2008) PDF
- Links out: EIS public e-tasks (eis.harno.ee), web-based level tests (web.meis.ee/testest), B1 intro video (YouTube)

**Mock-exam runner:** timed section mode; reading/listening auto-graded via hand-entered `answer_key` rows; writing → LLM rubric grade; speaking → exam-simulation conversation (§6.4) recorded for self-review. Output: per-section %, tracked across attempts, plotted against the 60% pass line and the 45% retake-lockout line.

**Phase switching driven by `exam_plan`:**
- **Build phase** (default): course chapters + vocab + light speech practice.
- **Exam phase** (auto-suggested at T−60 days): daily mix rebalances toward mock tasks, past-paper drills, writing/speaking simulations; consultation date surfaced.
- **Go/no-go gate** at registration deadline: recommend registering only if last two mocks ≥70% average with no section <50% (buffer above the 60% bar; avoids the 6-month lockout).

---

## 8. Motivation layer & engagement design

**Design principle:** the learner is an adult solo student whose previous attempts failed on motivation, not ability. Gamify *evidence of real competence*, never activity for its own sake. No guilt mechanics, no loss-aversion pressure, no XP confetti for trivial taps — engagement with the app must always equal engagement with the language.

### 8.1 Core mechanics

- **Daily goal:** default 25 min/day, 6 days/week, 1 grace day/week (streak survives one miss). Configurable but deliberately small — the failure mode of past attempts was ambition, not laziness.
- **Daily quest card:** three concrete micro-tasks sized to the daily goal (e.g. "12 vocab reviews · 1 Keeleklikk section · 2-min speaking drill"), auto-composed from due SRS items, next chapter, and current phase. Completing the card = streak day. One decision to make: none.
- **Streak + calendar heat-map**, fed by `activity_log` (auto-logged in-app time; course webview time via focus tracking; manual "+15 min offline study" button for honesty).
- **Notifications:** one neutral daily nudge at a chosen hour (Android); macOS menu-bar residence with streak glyph. Never guilt-toned.

### 8.2 The Trail (signature home screen)

The app's namesake, made literal: one winding path through all 29 chapters — 0 → A2 (ch. 16 gate) → B1 (ch. 29 gate) → exam flag — with the learner's marker standing at the current position. Chapters render as waypoints (done / current / locked-by-sequence-only-visually); A2 completion and each passed mock are landmarks on the path. Every app open shows distance covered before anything else.

### 8.3 Stats & readiness (honest flattery)

- **Exam-readiness gauge** on the dashboard — the centerpiece stat. Composite of recent mock-section scores, vocab mastered, and syllabus coverage, displayed against the 60% pass line (and the 45% lockout line). Answers the only question that matters: "am I on track to pass?"
- **Competence stats:** words known (FSRS state ≥ review), pronunciation accuracy trend (§6.3 scores over time), total listening minutes, writing submissions + rubric trend, mock trajectory chart.
- **Milestone badges tied to real events only:** first full conversation, first mock section >60%, A2 syllabus complete, first offline-day survived streak, exam registered. No badge inflation.
- **Weekly postcard:** Sunday summary — minutes, streak, new words, one Estonian sentence from this week's material that would have been unreadable a month ago. Rendered as a polished shareable card even if never shared.

### 8.4 Visual language & themes

Theming is a **token layer** (colors, type scale, radii, motion durations) above shared components — themes are switchable in settings without touching feature code. Two ship at launch:

- **Vaikus** ("stillness") — calm Nordic-minimal default: generous whitespace, warm off-white / deep charcoal surfaces, single muted teal accent, restrained motion. A study, not a slot machine.
- **Põhjavalgus** ("northern lights") — the energetic alternative: near-black surfaces with aurora gradient accents (green→violet), higher-contrast stats, slightly livelier progress motion. Same layout, different temperature — for days when calm reads as flat.

Both include proper light/dark handling (Põhjavalgus is dark-native), large readable Estonian type, and tap-to-hear on every Estonian string. Desktop (Studio) and mobile (Companion) share the design system; the Trail and quest card adapt per form factor. Additional themes are cheap once the token layer exists.

**Roadmap placement:** Trail, quest card, streak/heat-map, readiness gauge skeleton → **M1** (they *are* the core loop, not polish). Stats deepen as their data sources land (M2 mocks, M3 speech). Badges, postcard, animation polish → **M5**.

---

## 9. Sync design

- **Supabase** free tier: Postgres tables mirroring §4, single user row-level security, email+password auth.
- **Flow:** every local write appends to an outbox; background push when online; pull-merge on app focus. LWW per row on `updated_at`; `activity_log` and `review_log` are append-only (no conflicts by construction); streaks/progress % always recomputed locally from logs.
- Media (audio cache, archive mirror, exam PDFs) does **not** sync — each device fetches its own; only metadata rows sync.
- Escape hatch: everything exportable as JSON + the SQLite file itself is documented — no lock-in to Supabase.

---

## 10. Tech stack summary

| Concern | Choice |
|---|---|
| Framework | Flutter (stable channel), Dart 3 |
| Local DB | Drift (SQLite) |
| Sync | Supabase (postgrest + realtime optional) |
| Webview | webview_flutter (+ macOS WKWebView wrapper) |
| Audio record/play | record + just_audio |
| STT | whisper.cpp via FFI, model: TalTechNLP/whisper-large-et (GGML) |
| TTS | Neurokõne REST API + local file cache |
| LLM | OpenAI-compatible client → LM Studio (local) / Anthropic API (cloud) |
| SRS | FSRS (Dart port or direct implementation) |
| PDF viewing | pdfx or native viewer handoff |
| Archiver spike | Playwright (Node) standalone script, output consumed by app |
| Local static serve | shelf (Dart) on 127.0.0.1 |
| Secrets | flutter_secure_storage (Keychain / Keystore) |

---

## 11. Milestone plan

No calendar dates — sequenced by dependency, each with acceptance criteria. Ship each milestone as a usable increment; **start studying at M1**, the rest of the build runs alongside.

**M0 — Walking skeleton.** Flutter project, Android + macOS targets build and run; Drift schema v1; Supabase project + auth; CI (build both targets). ✅ *Accept: same dummy record created on Mac appears on phone.*

**M1 — Tracker core (the motivation app).** Seeded syllabus (16+13 chapters); chapter checklist + progress %; webview course embed with persistent login + "continue" deep-link; activity log, daily goal, streak + heat-map; exam countdown from `exam_plan`; Trail home screen, daily quest card, readiness-gauge skeleton (§8). ✅ *Accept: a full day's real study loop — open app, see next action, do Keeleklikk in-app, tick chapter, streak updates, syncs both ways.*

**M2 — Exam vault.** AssetService downloads all §7 assets; in-app PDF viewer + audio player; answer-key entry UI; mock-exam runner for reading + listening with auto-scoring and history chart. ✅ *Accept: complete a timed listening mock end-to-end and see % vs pass line.*

**M3 — Speech studio (macOS).** Neurokõne TTS with cache + speaker icons everywhere; whisper-large-et local transcription; pronunciation drill with word-level highlighting; conversation mode with hybrid LLM switch (LM Studio + Claude adapters, per-feature policy); writing feedback with rubric; corrections → SRS cards. ✅ *Accept: 10-min spoken conversation fully offline except LLM-in-cloud-mode; exam speaking simulation runs both official task formats timed.*

**M4 — Offline mirror spike (timeboxed 2 days).** Execute §5.2 protocol on Keeleklikk ch. 1; written findings; implement the highest level that proved viable (likely level 1, media harvest) or record "webview only" decision. ✅ *Accept: decision documented; if viable, chapter media playable offline in-app.*

**M5 — Companion completion.** Vocab SRS review UI (phone-first); Android speech via hub mode (mDNS → Mac) with cloud fallback; notifications; menu-bar streak on macOS; badges, weekly postcard, animation/visual polish pass (§8). ✅ *Accept: vocab review on phone offline, syncs; phone speech drill works on home LAN.*

**M6 — Exam phase features.** Phase auto-switch at T−60; go/no-go gate logic; full four-section mock assembly; consultation/registration reminders wired to real 2026–27 dates. ✅ *Accept: dry-run full mock exam in one sitting, scored, with recommendation output.*

---

## 12. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Building the app becomes procrastination from studying | M1 is deliberately small and study-usable; studying starts at M1, not M6 |
| Course sites redesign / break embed or archive | Syllabus is seed data, not scraped; webview degrades to external browser; archive is bonus tier |
| whisper.cpp GGML conversion of whisper-large-et fails | medium-et fallback; faster-whisper sidecar as plan C |
| Local LLM gives wrong Estonian corrections | Per-feature backend policy; local corrections labeled unverified; cloud default for grading |
| Neurokõne API terms change / rate limits | Aggressive caching; on-device TTS path exists (neurokone_app reference) |
| Harno reshuffles asset URLs | Assets downloaded once + checksummed; registry re-verified each exam cycle |
| Exam format changes | Format sourced from official 2026 pages; re-verify at each registration window |

## 13. Open questions (decide before M3)

1. Anthropic API key already available for cloud mode, or set up fresh?
2. Which LM Studio model to standardize on for local mode (test top candidates' Estonian in M3)?
3. Exam target: 8 Nov 2026 realistic only if study starts now and M1 lands fast — or aim Q1 2027 and keep pressure low? (Affects `exam_plan` seed only; nothing structural.)

---

## Appendix A — Verified resource registry (July 2026)

| Resource | URL |
|---|---|
| Keeleklikk (0→A2, 16 ch.) | https://www.keeleklikk.ee |
| Keeletee (A2→B1, 13 ch.) | https://www.keeletee.edu.ee |
| Exam info + dates + sample tasks | https://harno.ee/eesti-keele-tasemeeksamid |
| Exam registration (EIS) | https://eis.harno.ee/ |
| Level self-tests | http://web.meis.ee/testest/ |
| B1 consultation workbook | harno.ee /documents/2026-01/B1_konsultatsioon_2021.pdf |
| B1 sooritusnäidis | harno.ee /documents/2021-07/B1-taseme-sooritusnaidis.pdf |
| B1 listening test MP3 + task MP3s | projektid.edu.ee (Konsultatsioonide materjalid) |
| „Iseseisev keelekasutaja" handbook | harno.ee /documents/2021-06/Iseseisev-keelekasutaja.pdf |
| Neurokõne TTS | https://neurokone.ee · api via github.com/TartuNLP/text-to-speech-api |
| Neurokõne mobile app (OSS) | https://github.com/TartuNLP/neurokone_app |
| Estonian Whisper models | huggingface.co/TalTechNLP/whisper-large-et · whisper-medium-et |

Next B1 exams: **06.09.2026** (reg. by 01.08) · **08.11.2026** (reg. by 01.10) · quarterly 2027.
