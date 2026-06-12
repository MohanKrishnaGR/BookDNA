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
| **P2 — AI** | Library GPT chat (streaming, `claude-haiku-4-5`), shelf analysis (`claude-fable-5`, structured output), force-directed knowledge graph, server-side quotas | ✅ Built & verified (demo fallback until `ANTHROPIC_API_KEY` is set) |
| **P3 — Social + premium** | Challenges (server membership, locally computed progress), weekly leaderboard RPC scoped to your circle, monthly Wrapped story, paywall + server-granted 7-day trial entitlement | ✅ Built & verified (Play Billing wiring awaits a Play Console; trial is live) |

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

### AI features (Phase 2)

Edge Functions in `supabase/functions/`:

- `ai-chat` — Library GPT: streaming SSE from `claude-haiku-4-5` with a
  prompt-cached, pipe-delimited library context built server-side.
  Quotas: 10 messages/day free, 200/day premium (`ai_usage` table).
- `ai-analyze` — shelf analysis with `claude-fable-5` structured output
  (reading profile, blind spots, read-next picks, theme edges that feed
  the knowledge graph). Quotas: 1/month free, 8/month premium.

```powershell
supabase functions serve            # serves both functions locally
# enable real Claude calls (local):
#   create supabase/functions/.env containing ANTHROPIC_API_KEY=sk-ant-...
#   then restart `supabase functions serve --env-file supabase/functions/.env`
# cloud: supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
```

Without a key the functions return clearly-labelled demo responses so the
whole flow stays testable. The knowledge graph
([graph_physics.dart](lib/features/graph/graph_physics.dart)) renders genre
clusters immediately and adds dashed cross-cluster "bridge" edges once an
analysis has produced `theme_edges`; free tier shows the top 20 books.

### Social & premium (Phase 3)

- **Challenges** — global catalogue in Postgres, membership in
  `challenge_members`; progress (streak / finishes / genres this month) is
  computed from the member's own local data, so it works offline.
- **Leaderboard** — `weekly_leaderboard()` security-definer RPC returns
  weekly page totals for you + accepted `follows` only; friends' raw
  sessions are never exposed.
- **Wrapped** — auto-advancing monthly story
  ([wrapped_stats.dart](lib/features/wrapped/wrapped_stats.dart)) computed
  locally, with share-out.
- **Premium** — `profiles.premium_until` is server-set only via the
  `verify-purchase` function: one-time 7-day trial today; Play Billing
  receipt verification slots into the same endpoint once a Play Console
  service account exists (products `bookdna_monthly_199` /
  `bookdna_yearly_1499`). The entitlement is cached locally and gates the
  knowledge graph and AI quotas.
