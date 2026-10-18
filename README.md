# NOVA CRAFT

NOVA CRAFT is a native Flutter/Dart Android app for provisioning and managing Minecraft Java and Bedrock servers on GitHub Actions, with Playit.gg as an optional public tunnel. It retains the existing Flutter/Material 3 architecture; it is not a WebView.

- Package: `io.github.abiedadam0077.novacraft`
- Authentication: GitHub App Device Flow; no client secret or private key is embedded in the app.
- Languages: Arabic (RTL) and English (LTR); dark, light and system themes.
- Android: min SDK 26, target SDK 35, compile SDK 36, JDK 17.
- Flutter CI version: 3.35.7.

## Current build and verification

CI run [39124166880](https://github.com/abiedadam0077/NOVA-CRAFT/actions/runs/39124166880) completed successfully on commit `3a71772a856221c8ccd1d31e6acf704e882aff9c`. `flutter analyze`, `flutter test`, the APK build, `aapt` package/version checks, `apksigner` verification, SHA-256 generation, release upload, and CI re-download/checksum verification all passed.

- **Recommended arm64 direct download (25,290,261 bytes):** [NOVA-CRAFT-1.0.0-arm64-debugsigned.apk](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39124166880-1/NOVA-CRAFT-1.0.0-arm64-debugsigned.apk)
  SHA-256: `1bd16daeb6e1e99f24de9a980af33323edf086ddaa02a47d8172b9b52cf03d1a`
- **Universal direct download (61,328,979 bytes):** [NOVA-CRAFT-1.0.0-release-debugsigned.apk](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39124166880-1/NOVA-CRAFT-1.0.0-release-debugsigned.apk)
  SHA-256: `100a95fe3cf9154d382084eace0664fc1b49efdfb286574121e1b62b20d8f855`
- [Release page and verification reports](https://github.com/abiedadam0077/NOVA-CRAFT/releases/tag/flutter-apk-39124166880-1) · [SHA256SUMS.txt](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39124166880-1/SHA256SUMS.txt) · [apksigner report](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39124166880-1/signature-verification.txt)

These are AOT release-mode APKs but **debug-signed**, not production-signed. The repository contains no production keystore. A debug-signed APK can be used for testing, but it cannot update an installation signed by another key. CI does not generate or replace a release key. The manually dispatched emulator smoke test was not run because the available GitHub integration returned HTTP 403 for workflow dispatch; see the final report for this and other limits.

## First run

After onboarding and GitHub sign-in, select a repository where the NOVA CRAFT GitHub App has write access, or create a private repository and install the app on it. The repository is selected **before** Playit setup so the agent key can be written directly as the repository's encrypted `PLAYIT_SECRET_KEY` Actions Secret.

Playit is optional. To use it:

1. Create a Playit Agent and copy its `SECRET_KEY`. Save the key in NOVA CRAFT; the app writes it as the repository's encrypted GitHub Actions Secret. Saving it is **not** proof that the Agent has started or connected.
2. Start the server cycle from NOVA CRAFT. The GitHub Runner downloads the pinned official `playitd` binary, verifies its SHA-256, and starts it once with `--secret-path` and `--platform-docker`; the secret is kept in a temporary mode-0600 file and is not printed.
3. Wait for the runner status to report **Agent connected**. Only then create a Minecraft Java Tunnel manually in Playit, choose that connected Agent, select TCP, and target `127.0.0.1:25565`. The app/runner never creates a Tunnel.
4. The runner reports **Connection ready** only after the local Minecraft Java Server List Ping succeeds and the public address reported by Playit answers a real game-protocol ping. Missing, unsupported, or unallocated tunnels remain separate states. If the official Agent API does not return an address, enter a known `host:port` manually in Network settings; that override is for the app's direct ping only and does not make the runner claim that its Playit Tunnel is connected.

Playit may be skipped during setup and linked later from Network settings. The screen distinguishes Secret saved, Agent starting/connected/failed, Tunnel state, local server-port status, and externally verified connection. Runner Agent logs are bounded and redacted before publication. The GitHub Actions server cycle is temporary rather than 24/7 hosting.

## Server lifecycle

Each server uses its own GitHub repository and generated `.github/workflows/novacraft-server.yml` workflow. The runner is limited to a five-hour runtime budget inside GitHub Actions' six-hour job limit; it is not a 24/7 hosting service. Automatic continuation dispatches another cycle only when enabled and the server was not explicitly stopped. GitHub Actions quotas, queueing, runner availability, network access, and the repository plan apply.

The workflow validates the relative data path before cache restore and again before runner operations. It reapplies settings from `server.json`, downloads pinned server builds with checksum verification where provided, and waits for a real Java/Bedrock readiness signal before reporting the process as ready. Status and log files are published to the server repository; console commands are size/control-character checked, the internal `nova:` namespace is reserved, and manual commands can be disabled.

## Backups and restore

Backups include the edition's world data and relevant server settings, are created only after Java or Bedrock confirms its save operation, and are ZIP-CRC and SHA-256 checked locally and again after download from GitHub Releases. A verified marker is written only after the published archive has been downloaded and checked. The app lists only non-draft releases for the current server that contain both the expected ZIP and checksum assets; older unmarked backups are identified as needing verification. Restore validates the tag, checksum, archive paths and size limits, and rolls back partially replaced world data on failure.

The configurable retention is a number of backups (2–30), not days. Old releases are considered for pruning only after the new archive has been verified; unverified, incomplete or foreign-server releases are not pruning candidates. The app can open the exact `world-backup.zip` asset for download or queue a safe restore.

## Build and tests

Run locally with Flutter installed:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

CI also has a manually dispatchable Android emulator smoke workflow. A CI build, a successful APK signature/hash check, an emulator smoke test, and a live GitHub/Playit/Minecraft server test are separate claims; the final report records exactly which were run. External account credentials and a real Minecraft/Playit setup are required for end-to-end service testing.
