# BookDNA

**Understand your reading life. Turn your bookshelf into insights.**

A Material 3 Flutter app that decodes your personal library: Shelf DNA, reading
personality, evolution, diversity radar, library worth (₹), reading tracker
with streaks — plus (upcoming) AI chat over your own shelf and a knowledge
graph.

Built from the Claude Design prototype in `design/` (see
`design/home-library/README.md`). The full development plan covering all
phases lives in the repo owner's plan file; phase status below.

## Status

| Phase | Scope | Status |
|---|---|---|
| **P1 — Personal core** | Library (4 views), barcode scanner + ISBN import, book details (notes/rating/lend/share), reading tracker (sessions, streaks, heatmap), insights (DNA donut, personality, evolution, radar, worth), home dashboard, goal editor, settings, CSV export | ✅ Built (offline-first, local Drift DB, seeded demo library) |
| **M1.6 — Auth + sync** | Supabase auth (email + anonymous guest, guest→account upgrade), offline-first LWW sync engine (push/pull/watermarks/tombstones), RLS schema, badges + achievements | ✅ Built & verified against local Supabase (`supabase start`) |
| **P2 — AI** | Library GPT chat + shelf analysis via Claude (Supabase Edge Functions), knowledge graph | Planned |
| **P3 — Social + premium** | Challenges, leaderboard, friend feed, wrapped story, Play Billing paywall | Planned |

## Architecture

- **Flutter** (Material 3, seed `#0b57d0`, Figtree type scale, per-book HCT
  accent palettes → procedural typographic covers)
- **Riverpod** for state, **go_router** for navigation (5-tab shell + pushed
  screens), **Drift** (SQLite) as offline source of truth
- **fl_chart** + CustomPainters for the insight visualizations
- All stats are pure functions in
  `lib/features/insights/logic/formulas.dart` (unit-tested)
- ISBN lookup: Google Books → Open Library fallback
  (`lib/features/import/metadata_repository.dart`)

```
lib/
├─ app/            # MaterialApp, router, theme (tonal system, type scale, accents)
├─ core/           # Drift db + seed data, providers, formatters
├─ widgets/        # design system: BookCover, Ring, Stars, StatusBadge, …
└─ features/       # feature-first screens: home, library, scanner, import,
                   # book_details, tracker, insights, profile, community,
                   # notifications, settings, onboarding, auth
```

## Develop

```powershell
flutter pub get
dart run build_runner build        # regenerate Drift code after schema changes
flutter analyze
flutter test                       # formulas + sync engine + widgets
flutter run                        # pick the Android emulator
```

First launch seeds a 20-book demo library (the design persona) so every
insight renders; real books join via the scanner FAB.

### Backend (sync + auth)

```powershell
supabase start                     # local stack (Docker); applies supabase/migrations
flutter run --dart-define=SUPABASE_URL=http://10.0.2.2:54321 `
            --dart-define=SUPABASE_ANON_KEY=<publishable key from `supabase status`>
```

Without the dart-defines the app runs fully local (guest mode, no sync).
For production, point the defines at a Supabase cloud project and apply
`supabase/migrations` with `supabase db push`. Sync design: local Drift is
the source of truth; dirty rows push as batched upserts, pulls are
incremental on the server-set `server_updated_at` watermark, conflicts
resolve row-level last-writer-wins on the client clock
([sync_engine.dart](lib/core/sync/sync_engine.dart)).
