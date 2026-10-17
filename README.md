# NOVA CRAFT

**Flutter (Dart) app** — a complete rewrite of the original Kotlin/Compose build — to create and
manage Minecraft Java & Bedrock servers using **GitHub Actions** as the runner and **Playit.gg** for
public connectivity. There is no WebView and no HTML shell: every screen is a native Flutter
widget rendered with Material 3.

- Package / applicationId: `io.github.abiedadam0077.novacraft` (unchanged)
- GitHub App: `nova-craft-by-abiedadam0077` (App ID 5353235, Client ID `Iv23linL1Tf6ResSgUqL` — public identifiers only)
- Auth: GitHub App **Device Flow** (no client secret, no private key, no redirect URI inside the app)
- Languages: Arabic (default, full RTL) and English; themes: dark, light, system
- minSdk 26, targetSdk 35, compileSdk 36, JDK 17, Flutter 3.35.7

## Download the latest APK

Every successful CI run publishes a prerelease with directly downloadable APKs:

- Latest releases: <https://github.com/abiedadam0077/NOVA-CRAFT/releases>
- `NOVA-CRAFT-1.0.0-arm64-debugsigned.apk` — recommended for phones (arm64, ~25 MB)
- `NOVA-CRAFT-1.0.0-release-debugsigned.apk` — universal build (~60 MB)

The repository does not hold the original release keystore, so CI publishes **AOT release builds
signed with the CI debug key**. They are installable previews, not production-signed releases, and
an APK signed by a different key cannot update an existing installation in place. When
`NOVA_KEYSTORE_BASE64` / `NOVA_KEYSTORE_PASSWORD` / `NOVA_KEY_ALIAS` are configured, CI builds and
publishes a normally signed release instead. No replacement release key is generated automatically.

## Build pipeline

CI (`.github/workflows/flutter.yml`) uses JDK 17, Flutter 3.35.7 and Android SDK 36:

1. `flutter pub get`, `flutter analyze`, `flutter test` (unit + widget tests).
2. `flutter build apk` — release with the configured keystore, otherwise release builds signed with
   the CI debug key (universal + arm64 split).
3. Verifies package name, version, signature and SHA-256 of every APK with `aapt` / `apksigner`.
4. Publishes a `flutter-apk-<run-id>-<attempt>` prerelease, then re-downloads the asset and checks
   its hash before reporting the direct link.

Locally:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## Not verified on a physical device

`flutter analyze` and the test suite pass in CI, and the APKs above were built and verified there.
No physical Android device or authenticated GitHub account was available to this build, so the
Device Flow sign-in, live repository discovery, starting a real server, console streaming, file
editing, Modrinth installs, backups/restores and Playit.gg tunnels are **not** exercised end-to-end.
Bedrock edition creation is intentionally unavailable in the UI. GitHub-hosted runners are not a
24/7 host: a server stops when its workflow ends.

## How a server runs

Each server lives in its own GitHub repository containing `nova-craft/server.json`,
`server/server.properties` and `.github/workflows/novacraft-server.yml`. A workflow cycle
(max ~5h inside GitHub's 6h job limit) restores the latest backup Release, downloads the official
server build, optionally starts the pinned Playit agent (`v1.0.10`) with the repo's
`PLAYIT_SECRET_KEY` Actions secret, serves commands queued by the app, heartbeats to
`nova-craft/status.json`, then saves, uploads a verified backup Release and optionally dispatches
the next cycle. Ping/player counts are measured on the phone with real Java SLP / Bedrock RakNet pings.
