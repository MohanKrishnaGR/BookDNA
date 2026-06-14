# BookDNA — Data, Backend & Pilot Readiness

_Last updated: 2026-06-12. Companion to the phased build (see git history + README)._

---

## 1. Demo account (seeded & verified)

A fully-populated demo user now exists in the backend, reproducible from
[`supabase/seed_demo.sql`](../supabase/seed_demo.sql).

| | |
|---|---|
| **Email** | `mohankrishnagr08@gmail.com` |
| **Password** | `bookdna-demo-2026` |
| **Contents** | 20 books · 107 reading sessions (live 23-day streak + 18-week heatmap) · 2 notes · 2 lends (1 overdue) · 1 yearly goal · 1 cached AI analysis (drives the knowledge graph) · 2 joined challenges · **active premium trial** (public profile) |

Apply it to **any** Supabase project (local or cloud):

```bash
# local
Get-Content supabase/seed_demo.sql -Raw | docker exec -i supabase_db_BookDNA psql -U postgres -d postgres
# cloud
psql "$DATABASE_URL" -f supabase/seed_demo.sql
```

The seed is idempotent — re-running refreshes data and keeps the streak/heatmap
relative to "today". Verified: login works, all rows read back through RLS, the
leaderboard RPC returns the demo user, and the premium trial is active.

> The seed inserts the auth user directly in SQL, including the GoTrue
> empty-string token-column fix that SQL-seeded users need to log in.

---

## 2. Everything the app displays — and where it comes from

The defining architectural fact: **most of what you see is _computed_, not
stored.** The app persists a small set of raw facts and derives every insight on
device. Only three categories actually live server-side beyond the raw library.

### Raw data (persisted)

| Data | Acquired by | Local store (Drift/SQLite) | Server (Postgres) | Synced |
|---|---|---|---|---|
| **Books** (title, author, genre, pages, year, price, est. value, status, progress, current page, rating, hueShift, ISBN, publisher, language, description, cover URL, dates) | Barcode scan → ISBN lookup, manual add, or demo seed | `books` | `public.books` | ✅ LWW |
| **Reading sessions** (date, pages, minutes) | Log-session sheet in the tracker | `reading_sessions` | `public.reading_sessions` | ✅ append-only |
| **Notes / highlights** | Book details sheet | `notes` | `public.notes` | ✅ append-only |
| **Lends** (book, person, dates, returned) | Book "⋮ → Lend" sheet | `lends` | `public.lends` | ✅ LWW |
| **Goals** (year, target) | Goal editor sheet | `goals` | `public.goals` | ✅ LWW |
| **Activity feed** (icon, text, time) | Side-effect of user actions | `activities` | — | local-only |
| **Preferences** (dark mode, joined-challenge cache, premium cache, sync watermarks, app phase) | Settings + app state | `prefs`, `sync_meta` | — | local-only |

### Derived data (computed on device, never stored)

All of this is recomputed from the raw tables above by pure functions in
[`formulas.dart`](../lib/features/insights/logic/formulas.dart) /
[`personality.dart`](../lib/features/insights/logic/personality.dart) and the
Wrapped/challenge logic:

> Owned/read/unread counts · current & best streak · reading speed (pp/hr) ·
> days-to-finish · velocity · Shelf DNA genre donut · Reading Personality
> (8-archetype rule engine) · evolution curve · 18-/9-week heatmaps · 6-axis
> diversity radar + weakest axis · author analytics · library worth (₹) ·
> unread-knowledge stats · knowledge age · level/XP · the 8 badges · the monthly
> **Wrapped** story · per-challenge progress.

Because these are derived, they cost nothing to store, never drift out of sync,
and work fully offline.

### Server-computed / server-only data

| Data | Source | Storage |
|---|---|---|
| **AI shelf analysis** (profile, blind spots, read-next, theme edges) | `ai-analyze` Edge Function → Claude `claude-fable-5` (structured output) | `public.ai_analyses` + cached in `prefs` for offline |
| **AI chat** (Library GPT) | `ai-chat` Edge Function → Claude `claude-haiku-4-5` (streaming) | not stored (ephemeral); token usage → `ai_usage` |
| **AI quotas** | incremented per call via `bump_ai_usage` RPC | `public.ai_usage` |
| **Challenge catalogue** | global, service-role managed | `public.challenges` (+ built-in fallback list) |
| **Challenge membership** | join/leave | `public.challenge_members` + `prefs` cache |
| **Weekly leaderboard** | `weekly_leaderboard()` security-definer RPC (aggregates your + friends' pages) | computed, not stored |
| **Premium entitlement** | `verify-purchase` Edge Function | `public.profiles.premium_until` (service-role-set only) + `prefs` cache |
| **Friend graph** | follow/unfollow (UI pending) | `public.follows` |

### External data acquisition

| Need | Provider | Notes |
|---|---|---|
| Book metadata from ISBN | **Google Books** (`country=IN`) → **Open Library** fallback | Client-direct today; designed to move behind an `isbn-lookup` Edge Function for caching + key custody |
| Book covers | **Procedural typographic covers** (brand signature, generated on device) | Real cover URLs stored optionally; off by default |
| AI | **Anthropic Claude** via Edge Functions (key server-side) | Demo fallback when `ANTHROPIC_API_KEY` unset |

---

## 3. How the app works (data flow)

```
                    ┌──────────────── Flutter app (Android) ────────────────┐
  Scan / type ISBN ─┤  Google Books / Open Library → Import → local write   │
                    │                                                        │
  Everything reads  │   Drift (SQLite)  ← single source of truth →  Riverpod │
  from local first  │        │  ▲                                    (UI)    │
                    │        │  │ derive (formulas, personality, wrapped)    │
                    │   sync_engine (push dirty / pull by watermark / LWW)   │
                    └────────┼──┼────────────────────────────────────────────┘
                             ▼  │
              ┌──────────────────────────── Supabase ───────────────────────┐
              │  Postgres + RLS   Auth (email/anon)   Edge Functions (Deno)  │
              │  books, notes,    JWT per request     ai-chat  → Claude      │
              │  sessions, lends,                     ai-analyze→ Claude     │
              │  goals, profiles,                     verify-purchase        │
              │  challenges,                          (+ planned isbn-lookup)│
              │  follows, ai_*     RPCs: weekly_leaderboard, bump_ai_usage   │
              └──────────────────────────────────────────────────────────────┘
```

**Offline-first.** The local Drift DB is the source of truth; the UI only ever
reads local streams. The sync engine pushes dirty rows as batched upserts, pulls
incrementally on a server-set `server_updated_at` watermark, and resolves
conflicts row-level last-writer-wins on the client clock. Sessions and notes are
append-only (conflict-free). Guest (anonymous) users can use everything and later
upgrade to a real account, keeping their data.

---

## 4. Backend: Supabase vs Firebase

**Chosen: Supabase**, and it is the right fit for this product. Here is the
reasoning, since "Firebase or something" is an explicit open question.

| Dimension | Supabase (current) | Firebase | Why it matters for BookDNA |
|---|---|---|---|
| Data model | **Relational Postgres** | NoSQL (Firestore) | The app is inherently relational — books↔sessions↔notes↔lends, `GROUP BY genre`, `SUM(pages)`, leaderboard aggregates. SQL is a natural fit; Firestore would force denormalization and client-side aggregation. |
| Insights/leaderboard | SQL aggregates + RPCs | Cloud Functions + manual fan-out/counters | Weekly leaderboard is one `security definer` SQL function. In Firestore you'd maintain counter documents. |
| Access control | **Row-Level Security** (declarative, in the DB) | Security Rules (separate DSL) | RLS keeps authorization next to the data and is already written + advisor-clean. |
| Server compute | Edge Functions (Deno/TS) | Cloud Functions (Node) | Comparable. Both host the Claude key server-side. |
| Auth | Email, anonymous, OAuth, magic link | Similar | Both fine; anonymous→permanent upgrade is first-class in Supabase. |
| Offline sync | We own it (Drift + sync engine) | Firestore has built-in offline cache | Firestore's offline is convenient but opaque; our explicit engine gives full control over conflict policy and is already built + tested. |
| Vendor lock-in | Low — **portable Postgres** | Higher — proprietary Firestore | A pilot that might move clouds later benefits from standard Postgres + `pg_dump`. |
| Local dev | Full stack in Docker (used throughout) | Emulator suite | Both good; we've been developing against the local stack end-to-end. |
| Cost at pilot scale | Free tier covers a closed pilot comfortably | Free (Spark) tier also fine | Neither is a cost concern at < a few hundred users. |

**Verdict:** keep Supabase. Firestore would add NoSQL modeling friction precisely
where this app is most relational (analytics, leaderboards) with no offsetting
win. Firebase would only become attractive if you later wanted Google-native push
(FCM) + Analytics + Crashlytics as one bundle — and those three can be added
_alongside_ Supabase (FCM for push, Crashlytics/Sentry for crashes) without
moving the database.

**Recommended additions (provider-agnostic), not a backend switch:**
- **Crash/error reporting** — Sentry or Firebase Crashlytics.
- **Product analytics** — PostHog (self-host or cloud) or Firebase Analytics.
- **Push notifications** — FCM, when you move beyond in-app/local notifications.

---

## 5. Pilot readiness assessment

Scope matters: a **closed pilot** (Play internal testing / a TestFlight-style
group of ~10–50 invited users) is achievable with a short checklist. A **public
launch** needs more. Status below is for the closed-pilot bar.

### Scorecard

| Area | Status | Notes |
|---|---|---|
| Core app (library, scan, tracker, insights) | 🟢 Ready | Offline-first, 59 tests green, exercised on device |
| Data model + RLS | 🟢 Ready | Per-user isolation, advisors clean |
| Multi-device sync | 🟢 Ready | Push/pull/LWW/tombstones verified across two installs |
| AI (chat, analysis, graph) | 🟡 Wired, needs key | Functions deployed; returns demo output until `ANTHROPIC_API_KEY` is set |
| Social (challenges, leaderboard) | 🟢 Ready | Live; friend feed shows honest empty state until follows ship |
| Wrapped | 🟢 Ready | Computed from real data |
| Premium trial | 🟢 Ready | Server-granted 7-day trial works; **store billing not wired** |
| Auth — email + guest | 🟢 Ready | Works incl. guest→account upgrade |
| Auth — Google/Apple | 🔴 Not configured | Needs OAuth client IDs (Google Cloud / Apple) |
| Crash reporting / analytics | 🔴 None | No visibility into pilot failures yet |
| Cloud backend (prod) | 🟡 Local only | Need a cloud Supabase project + migrations + secrets |
| Legal (Terms / Privacy) | 🔴 None | Required for store listing + data collection |
| App store presence | 🔴 None | No signing config, listing, or icon/branding pass |
| ISBN lookup hardening | 🟡 Client-direct | Works; move behind `isbn-lookup` function for caching + quotas before scale |
| Real cover images | 🟡 Procedural only | Intentional brand choice; fine for pilot |
| Shelf-photo scan (premium feature copy) | 🔴 Unbuilt | Paywall copy promises it; keep honest or hide until built |
| Known bug: demo-seed merge | 🟡 Tracked | Fresh install seeds demo books that merge into an existing account on sign-in (chip filed) |

### Must-fix before a closed pilot
1. **Provision a cloud Supabase project**: `supabase link` + `supabase db push`
   (applies all 3 migrations), `supabase functions deploy`, and
   `supabase secrets set ANTHROPIC_API_KEY=…`. Then build with
   `--dart-define=SUPABASE_URL/SUPABASE_ANON_KEY` pointing at it.
2. **Configure Google sign-in** (and Apple if iOS) — or ship email-only and hide
   the OAuth buttons for the pilot.
3. **Add crash + error reporting** (Sentry/Crashlytics) — non-negotiable for a
   pilot; you need to see failures.
4. **Fix the demo-seed merge** so testers signing in don't get demo books mixed
   into their library (or disable the seed for signed-in users).
5. **Terms of Service + Privacy Policy** (you collect reading data and call an
   AI provider) and a delete-my-data path.

### Should-fix (soon after)
- Reading-reminder **local notifications** actually scheduled (UI exists; wiring
  pending), then FCM push.
- Move ISBN lookup behind the `isbn-lookup` Edge Function (cache + key custody).
- Either build shelf-photo recognition or remove it from paywall copy.
- A minimal **CI** (`flutter analyze` + `flutter test` on push) and DB backups on
  the cloud project.
- Basic **product analytics** to learn what pilot users actually do.

### Distribution for the pilot
- **Android**: Play Console **internal testing** track (up to 100 testers, no
  review delay) or direct APK to invitees. Premium trial works without Play
  Billing; defer store products.
- **iOS**: deferred — no signing/build set up yet; Android-first pilot is the
  fastest path.

### Risks & mitigations
- **AI cost** — bounded by per-user quotas (10 chat/day, 1 analysis/month free)
  and the demo fallback; watch the Anthropic spend dashboard.
- **Single region / no backups yet** — enable Supabase PITR/backups on the cloud
  project before inviting users.
- **Client-direct Google Books** — fine at pilot volume; has no key to leak
  (keyless), but add the proxy before scaling.

### Bottom line
The **product is feature-complete** across all three phases and verified
end-to-end. The gap to a **closed pilot** is operational, not architectural:
stand up a cloud project with secrets, add crash reporting + a privacy policy,
fix the seed-merge, and decide email-only vs OAuth. That is roughly a few days of
setup, not new feature work. A **public launch** additionally needs store
presence, billing, push, legal review, and monitoring.
