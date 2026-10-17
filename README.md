# NOVA CRAFT

Native Android app (Kotlin + Jetpack Compose + Material 3 — no WebView) to create and manage
Minecraft Java & Bedrock servers using **GitHub Actions** as the runner and **Playit.gg** for public connectivity.

- Package: `io.github.abiedadam0077.novacraft`
- GitHub App: `nova-craft-by-abiedadam0077` (App ID 5353235, Client ID `Iv23linL1Tf6ResSgUqL` — public identifiers only)
- Auth: GitHub App **Device Flow** (no client secret, no private key, no redirect URI inside the app)
- Phase 1 research & GitHub App setup sheet: `docs/PHASE-01-RESEARCH-AND-GITHUB-APP-AR.md`

## Download the verified preview

[Download NOVA CRAFT 1.0.0 APK (debug, 21 MB)](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/tested-apk-38998610684/NOVA-CRAFT-1.0.0-debug.apk)

[Published test report and evidence](https://github.com/abiedadam0077/NOVA-CRAFT/releases/tag/tested-apk-38998610684).
This is a debug-signed preview, not a production release signed with the original key.

## Build and direct APK delivery

CI (`.github/workflows/android.yml`) uses JDK 17, Gradle 8.11.1 and Android SDK 35:

1. Unit tests, Android lint, debug APK and instrumentation APK builds.
2. Uses the configured original release keystore **only if available**. Otherwise selects an
   explicitly named **debug** APK; it does not create a replacement release keystore.
3. Verifies the selected file with `apksigner verify --verbose --print-certs`, checks package
   metadata and writes SHA-256 checksums.
4. Runs Android 35 emulator tests (onboarding/auth screen, activity recreation, Android Keystore,
   native encryption), then installs and launches the **exact APK** selected for delivery.
5. Only after passing tests, publishes an `apk-<run-id>-<attempt>` GitHub prerelease with the APK,
   signature report, checksum and installation evidence; re-downloads the asset to check its hash.

Pushes on the session branch and `main`, or manual workflow dispatch, run the pipeline.
Test/lint reports are retained for 30 days as `nova-craft-delivery-<run-id>` Actions artifacts.
The release asset is a direct `.apk` download, not an artifact ZIP, and requires no manual key handling.

Locally, install JDK 17, Android SDK 35 and Gradle 8.11.1, then run:

```sh
gradle testDebugUnitTest lintDebug assembleDebug
gradle connectedDebugAndroidTest # with an Android emulator/device connected
```

## Signing status

The previous release run (38996606818) failed with **`NOVA_KEYSTORE_BASE64 secret is missing`**.
No original release keystore is present in this checkout; a signed production release must not be
claimed based only on a successful debug build. The CI attempts the existing configured release
secrets when present and never silently labels a debug APK as release.

`assembleRelease` fails without configured signing material. Private keys and local
`signing.properties` stay out of Git. Standard Android debug signing is used for an installable
preview if the original key is unavailable. Debug signing identities on fresh CI runners are not
stable; an older differently signed installation cannot be updated in place.

Emulator smoke tests do **not** prove real-phone compatibility or authenticated server flows.
See `docs/IMPLEMENTATION-STATUS-AR.md` for product limits and the attached release test report
for the exact checks that passed on a delivered build.

## How a server runs

Each server lives in its own GitHub repository containing `nova-craft/server.json`,
`server/server.properties` and `.github/workflows/novacraft-server.yml`. A workflow cycle
(max ~5h inside GitHub's 6h job limit) restores the latest backup Release, downloads the official
server build, optionally starts the pinned Playit agent (`v1.0.10`) with the repo's
`PLAYIT_SECRET_KEY` Actions secret, serves commands queued by the app, heartbeats to
`nova-craft/status.json`, then saves, uploads a verified backup Release and optionally dispatches
the next cycle. Ping/player counts are measured on the phone with real Java SLP / Bedrock RakNet pings.
