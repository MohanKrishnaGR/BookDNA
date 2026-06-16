# CI/CD

BookDNA ships through two GitHub Actions workflows. **CI** gates every change;
**release** delivers signed builds to Google Play's internal testing track.
Production promotion is always **manual** (staged rollout in Play Console).

## CI — `.github/workflows/ci.yaml`
Runs on every PR and every push to `main`. **No secrets, no setup.**
- `analyze-test` — `flutter analyze` + `flutter test --coverage` (uploads `lcov.info`).
- `build-debug` — `flutter build apk --debug`, a compile check for Gradle/Kotlin breakage.

Make it a gate: GitHub → Settings → Branches → protect `main` → require the
`Analyze & test` check to pass before merge.

## Release / CD — `.github/workflows/release.yaml`
Triggered by a tag `v*` (or the manual **Run workflow** button). It builds a signed,
obfuscated `.aab`, attaches it to a GitHub Release, uploads the Dart symbols as an
artifact, and pushes the bundle to the Play **internal** track.

The release pipeline is **inactive until the one-time setup below is done.**

### One-time setup

**1. Upload keystore**
```bash
keytool -genkeypair -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
Keep this file + passwords safe and OUT of git (already gitignored). Losing it means
you can't update the app.

**2. Play Console** (one-time $25 developer account)
- Create the app with package `com.bookdna.bookdna`.
- Finish the setup checklist; enable **Play App Signing**.
- Create an **Internal testing** track and add at least one tester email.

**3. Play service account** (for automated upload)
- In Google Cloud (project `bookdna-app-v1` is fine), create a service account and
  enable the **Google Play Android Developer API**.
- In Play Console → **Users and permissions** → invite the service account email,
  grant **Release to testing tracks** (at least Internal). Download its JSON key.

**4. Register signing SHA-1s for Google Sign-In** ⚠️
A Play-signed release is signed with a *different* key than your debug keystore, so the
debug SHA-1 currently registered won't match. In Firebase (`bookdna-app-v1`) → Project
settings → your Android app, add **both**:
- the **upload keystore** SHA-1 (`keytool -list -v -keystore upload-keystore.jks -alias upload`), and
- the **Play App Signing** SHA-1 (Play Console → Release → Setup → App signing).

Without this, Google Sign-In fails (`DEVELOPER_ERROR`) in the released build.

**5. GitHub repo secrets** (Settings → Secrets and variables → Actions)

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore store password |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | key password |
| `GOOGLE_SERVICES_JSON_BASE64` | `base64 -w0 android/app/google-services.json` |
| `ENV_JSON` | the full contents of your local `env.json` |
| `PLAY_SERVICE_ACCOUNT_JSON` | the service-account JSON from step 3 |

### Cutting a release
1. Bump `version:` in `pubspec.yaml` (versionName). The workflow sets versionCode from
   the run number automatically, so Play always accepts the upload.
2. Tag and push:
   ```bash
   git tag v1.0.1 && git push origin v1.0.1
   ```
3. The build lands on the **internal** track. Test it, then promote to production
   **manually** in Play Console with a staged rollout.

> The first internal-track upload sometimes must be done by hand in Play Console before
> the API will accept automated uploads — Google's one-time gate, not a workflow bug.
