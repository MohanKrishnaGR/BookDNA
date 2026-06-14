# BookDNA — Integration runbook (dashboard / UI, no CLI)

Three independent tracks via web consoles. Do Supabase first — OAuth and the app
both point at it.

Repo facts you'll reuse:
- Android package / `applicationId`: **`com.bookdna.bookdna`**
- App reads `SUPABASE_URL` / `SUPABASE_ANON_KEY` from `--dart-define`
- SQL to paste: `supabase/migrations/` (3 files, in name order)
- Functions to recreate: `supabase/functions/{ai-chat,ai-analyze,verify-purchase}`

The only things that can't be done in a browser: getting your signing **SHA-1**
(one `keytool` line, or Android Studio's Gradle **signingReport** UI), editing
two **Gradle** files, and adding **pub** packages. Everything else is clicks.

---

## Track 1 — Supabase (supabase.com/dashboard)

### 1.1 Create the project
New project → name `bookdna`, set a DB password (save it), pick a region near
your testers → **Create**.

### 1.2 Apply the schema — **SQL Editor**
Left nav → **SQL Editor → New query**. For **each** file below, open it in the
repo, copy the whole contents, paste, **Run**. Do them in this order:
1. `supabase/migrations/20260612075929_core_schema.sql`
2. `supabase/migrations/20260612091520_ai_tables.sql`
3. `supabase/migrations/20260612141821_social_premium.sql`

(Optional) seed the demo account: paste `supabase/seed_demo.sql` and **Run**.
Check **Table Editor** → you should see `books`, `challenges`, etc.

### 1.3 Auth settings — **Authentication**
- **Providers → Email**: enabled. For the pilot, turn **Confirm email** off
  (Authentication → Providers → Email → "Confirm email" toggle) so testers can
  sign in immediately.
- **Allow anonymous sign-ins**: Authentication → **Sign In / Providers** (or
  **Configuration**) → enable **"Allow anonymous sign-ins"**. Required — the
  guest button and the sync engine's adopt-and-push depend on it.

### 1.4 AI key — **Edge Functions → Secrets**
Edge Functions → **Secrets** → **Add new secret** →
name `ANTHROPIC_API_KEY`, value `sk-ant-...` → Save. (This flips the AI from
demo replies to real Claude once the functions exist.)

### 1.5 Edge Functions — **Edge Functions → Deploy a new function → Via Editor**
Create three functions and paste their code: `ai-chat`, `ai-analyze`,
`verify-purchase`.

> ⚠️ The repo's functions share helpers via `../_shared/*`. The browser editor
> deploys **one self-contained function at a time** and can't reach a sibling
> `_shared` folder. Two options:
> - **Easiest:** ask me to generate **paste-ready single-file** versions of each
>   function (helpers inlined) — then it's pure copy-paste into the editor.
> - Or, in each function's editor, add the `_shared` files **inside** that
>   function and change imports from `../_shared/x.ts` to `./x.ts`.

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically for
deployed functions — you don't set those.

### 1.6 Get the app's keys — **Project Settings → API / Data API**
Copy **Project URL** (`https://<ref>.supabase.co`) and the **anon / publishable**
key. Run the app pointing at them:
```
flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_ANON_KEY=<anon-key>
```
**Verify:** sign in with email on a device → the row shows up under
Table Editor → `books` after a sync.

---

## Track 2 — Google OAuth (console.cloud.google.com + Supabase dashboard)

Native sign-in: the app gets a Google **ID token**, Supabase verifies it. You
need a **Web** OAuth client (for verification) and an **Android** one (so the
device can issue tokens).

### 2.1 Google Cloud Console
1. Top bar → **create/select a project**.
2. **APIs & Services → OAuth consent screen** → External → fill app name +
   support email → add your email under **Test users** → Save.
3. **APIs & Services → Credentials → + Create credentials → OAuth client ID**,
   **twice**:
   - **Application type: Web** → Create → copy **Client ID** and **Client
     secret**.
   - **Application type: Android** → package `com.bookdna.bookdna` + your
     **SHA-1**. Get the SHA-1 from **Android Studio**: right panel **Gradle →
     bookdna → Tasks → android → signingReport** (double-click) → copy the
     `SHA1` under `debug`. *(CLI alternative: `keytool -list -v -keystore
     %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass
     android -keypass android`.)* For release, use your upload key's SHA-1.

### 2.2 Supabase dashboard → Authentication → Providers → Google
Enable **Google** → paste the **Web** client's **Client ID + Client secret** →
in **Authorized Client IDs** add the **Android** client ID (and the Web one) →
Save.

### 2.3 App code (small edit + one package)
- Add the package: in `pubspec.yaml` under dependencies add `google_sign_in: ^6.2.2`
  then run `flutter pub get` (or use the IDE's "pub get"). *(6.x matches the
  Supabase guide; 7.x renamed `signIn()`→`authenticate()`.)*
- In `lib/features/auth/auth_controller.dart` add a `signInWithGoogle()` that
  does `GoogleSignIn(serverClientId: <web client id>).signIn()` →
  `supabase.auth.signInWithIdToken(provider: OAuthProvider.google, idToken:…,
  accessToken:…)`. Pass the web client id via
  `--dart-define=GOOGLE_WEB_CLIENT_ID=…`. Wire the existing Google button in
  `auth_screen.dart` to call it. (Guest data is preserved — the sync engine
  adopts local rows under the new Google user on auth change.)
  *I can make this code edit for you.*

**Verify:** "Continue with Google" → account picker → Home; the user appears in
Supabase → Authentication → **Users** with provider `google`.

---

## Track 3 — Firebase Analytics + Crashlytics (console.firebase.google.com)

Adds Firebase **only as a telemetry layer** (crash reporting + product
analytics) — your database stays on Supabase.

**Status:** all app code + Gradle wiring is already done and build-verified.
Firebase is wired to **auto-activate** the moment `google-services.json` exists
(`android/app/build.gradle.kts` applies the Google plugins only
`if (file("google-services.json").exists())`, and `main.dart`'s
`Firebase.initializeApp()` is wrapped in try/catch). Until the file is added the
app builds and runs normally with telemetry off. **The only remaining work is
the console step below to produce that file.**

Already in the repo:
- packages `firebase_core`, `firebase_analytics`, `firebase_crashlytics`
- `lib/main.dart` — `runZonedGuarded` + `Firebase.initializeApp()` +
  `FlutterError.onError` / `PlatformDispatcher.onError` → Crashlytics
- `lib/core/analytics/analytics.dart` — safe no-op facade (`Analytics.instance`)
- `lib/app/router.dart` — `FirebaseAnalyticsObserver` → automatic `screen_view`
- custom events: `login{method}`, `book_added{genre,has_isbn}`,
  `reading_session_logged{pages,minutes}`, `book_finished{genre}`,
  `ai_analysis_run{is_demo}`, `trial_started{plan}`
- Gradle plugins declared (`settings.gradle.kts`, `apply false`) + conditional
  apply (`app/build.gradle.kts`)
- `.gitignore` excludes `google-services.json`

### 3.1 Firebase Console (the one manual step)
1. **Add project** → reuse the Google Cloud project from Track 2 (so Analytics
   shares the same GCP project) → create. Accept the Google Analytics step (it
   creates/links a GA4 property — required for Analytics).
2. On the project overview, click the **Android** icon ("Add app"):
   - **Android package name:** `com.bookdna.bookdna`
   - nickname `BookDNA` · SHA-1 optional (not needed for Crashlytics/Analytics;
     add the debug SHA-1 if you later use Firebase Auth/Dynamic Links) → Register.
3. **Download `google-services.json`** → place it at
   `android/app/google-services.json`. (Or paste me its contents and I'll write
   it.) That's it — the Gradle conditional picks it up automatically.
4. You can skip the console's "add the SDK / Gradle" pages — those edits are
   already in the repo. → Continue to console.
5. Left nav → **Release & Monitor → Crashlytics** → it activates after the first
   crash report is received (next step).

### 3.2 Rebuild + verify
```
flutter run --dart-define-from-file=env.json   # or build apk
```
- **Analytics:** enable debug view —
  `adb shell setprop debug.firebase.analytics.app com.bookdna.bookdna` — use the
  app, then watch **Firebase Console → Analytics → DebugView** for `screen_view`,
  `login`, `book_added`, etc. (Standard reports lag ~24h; DebugView is live.)
- **Crashlytics:** temporarily add `FirebaseCrashlytics.instance.crash();` behind
  a debug button (or `throw` in a handler), trigger it, relaunch the app (reports
  upload on next launch), confirm it lands in **Console → Crashlytics**, then
  remove the trigger.

---

## Keep out of git
`android/app/google-services.json`, any `env.json` of dart-defines, and never the
`ANTHROPIC_API_KEY` or Google **client secret** (those live only in Supabase
secrets / the Google provider config).
