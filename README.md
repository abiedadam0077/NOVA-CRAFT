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

## Navigation and first run

The app opens on a splash, then **GitHub Device Flow**, then **Playit.gg preparation**, then the
first-server wizard. The navigation bar does not exist before a real server does, and it has
exactly five destinations:

| # | Arabic | English | Contents |
|---|---|---|---|
| 1 | الرئيسية | Home | server identity, real status, address, Start / Stop / Restart |
| 2 | الكونسول | Console | real `nova-craft/live.log` tail (polling, never labelled live-streaming), commands, search, follow toggle |
| 3 | الملفات | Files | only `server/` data — path containment enforced |
| 4 | المودات | Mods | Modrinth mods (Fabric) and plugins (Paper/Purpur/Spigot), jar upload |
| 5 | إعدادات السيرفر | Server settings | Minecraft settings + EULA, network/Playit, run cycle, backups, worlds, account, app settings |

## Version and software support

* **Vanilla** — official Mojang manifest (`piston-meta`), including `javaVersion.majorVersion`.
* **Paper** — `fill.papermc.io/v3` only (the old `api.papermc.io/v2` was disabled on 2026-07-01),
  stable channel, checksum verified via `sha256`.
* **Purpur** — `api.purpurmc.org/v2`, latest build, MD5 verified.
* **Fabric** — `meta.fabricmc.net/v2` with a stable loader + the vanilla server jar.
* **Forge / NeoForge** — deliberately **not offered**: there is no reliable per-version resolution
  path, and the app never shows versions it cannot actually download and run.

Java is selected per version: `≤1.16 → 8`, `1.17 → 16`, `1.18–1.20.4 → 17`,
`1.20.5+/1.21.x → 21`, `26.x → 25`.

## How a server runs

Each server lives in its own GitHub repository containing `nova-craft/server.json`,
`nova-craft/config.py`, `nova-craft/runner.sh` and `.github/workflows/novacraft-server.yml`.
A cycle (`timeout-minutes: 330`, inside GitHub's 6h limit):

1. restores the Actions cache and, if present, the newest `backup-<id>-*` Release (checksum checked);
2. rewrites `server.properties` from `server.json` so app edits always win over the cache;
3. writes `eula.txt` **only** when the user accepted the EULA, otherwise refuses to start;
4. downloads the server build and verifies its SHA-256/SHA-1/MD5;
5. starts the Playit agent with `PLAYIT_SECRET_KEY`, reads the assigned public address from the
   agent log and probes it over TCP before reporting the tunnel as connected;
6. waits for a real `Done (Xs)!` / `Server started` line before publishing `ready`;
7. publishes `nova-craft/status.json` every 30 s and the log tail to `nova-craft/live.log` every
   ~30 s, and drains `nova-craft/commands/`;
8. on stop: `save-off` → `save-all flush` → verified `world-backup.zip` Release → `stop`.

Because a workflow is not a 24/7 host, the app states the cycle limit and relies on the next
dispatch (or auto-restart) instead of pretending the server is always online.
