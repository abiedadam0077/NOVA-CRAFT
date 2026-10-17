# NOVA CRAFT

Native Android app (Kotlin + Jetpack Compose + Material 3 — no WebView) to create and manage
Minecraft Java & Bedrock servers using **GitHub Actions** as the runner and **Playit.gg** for public connectivity.

- Package: `io.github.abiedadam0077.novacraft`
- GitHub App: `nova-craft-by-abiedadam0077` (App ID 5353235, Client ID `Iv23linL1Tf6ResSgUqL` — public identifiers only)
- Auth: GitHub App **Device Flow** (no client secret, no private key, no redirect URI inside the app)
- Phase 1 research & GitHub App setup sheet: `docs/PHASE-01-RESEARCH-AND-GITHUB-APP-AR.md`

## Build

CI builds on GitHub Actions (`.github/workflows/android.yml`) with JDK 17 + Gradle 8.11.1:

- Push → unit tests + `assembleDebug`, APK uploaded as the `nova-craft-debug` artifact.
- Manual dispatch with `release=true` → signed `assembleRelease` (keystore decoded from the
  `NOVA_KEYSTORE_BASE64` secret), `apksigner verify` + SHA-256, APK uploaded as `nova-craft-release`.

Locally: install JDK 17 + Android SDK 35, run `gradle wrapper --gradle-version 8.11.1` once, then `./gradlew assembleDebug`.

## Signing

The release keystore (PKCS12) is generated once, stored **only** as GitHub Actions secrets
(`NOVA_KEYSTORE_BASE64`, `NOVA_KEYSTORE_PASSWORD`, `NOVA_KEY_ALIAS`, `NOVA_KEY_PASSWORD`) plus the
owner's offline backup. It is never committed. Losing it means future updates cannot be installed
over existing installs — back it up.

## How a server runs

Each server lives in its own GitHub repository containing `nova-craft/server.json`,
`server/server.properties` and `.github/workflows/novacraft-server.yml`. A workflow cycle
(max ~5h inside GitHub's 6h job limit) restores the latest backup Release, downloads the official
server build, optionally starts the pinned Playit agent (`v1.0.10`) with the repo's
`PLAYIT_SECRET_KEY` Actions secret, serves commands queued by the app, heartbeats to
`nova-craft/status.json`, then saves, uploads a verified backup Release and optionally dispatches
the next cycle. Ping/player counts are measured on the phone with real Java SLP / Bedrock RakNet pings.
