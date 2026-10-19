# NOVA CRAFT

NOVA CRAFT is a native Flutter/Dart Android app for provisioning and managing Minecraft Java and Bedrock servers on GitHub Actions, with Playit.gg as an optional public tunnel. It retains the existing Flutter/Material 3 architecture; it is not a WebView.

- Package: `io.github.abiedadam0077.novacraft`
- Authentication: GitHub App Device Flow; no client secret or private key is embedded in the app.
- Languages: Arabic (RTL) and English (LTR); dark, light and system themes.
- Android: min SDK 26, target SDK 35, compile SDK 36, JDK 17.
- Flutter CI version: 3.35.7.

## Current build and verification

CI run [39339756155](https://github.com/abiedadam0077/NOVA-CRAFT/actions/runs/39339756155) completed successfully on commit `828a0218748ae8dbec016d05f79976ca67eb33ad`. With Flutter 3.35.7, `flutter analyze` and the complete `flutter test` suite passed, including regression tests for large Modrinth JAR uploads racing with Runner commits; both APKs were built, verified, published as a public prerelease, then downloaded by CI and checked against SHA-256.

- **Recommended arm64 direct download (27,373,741 bytes):** [NOVA-CRAFT-1.0.0-arm64-debugsigned.apk](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39339756155-1/NOVA-CRAFT-1.0.0-arm64-debugsigned.apk)
  SHA-256: `d4de3a277ba7144a1301964d14e61b2d8aa5f81368ba2c67e8be77a5c3bd2051`
- **Universal direct download (63,935,243 bytes):** [NOVA-CRAFT-1.0.0-release-debugsigned.apk](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39339756155-1/NOVA-CRAFT-1.0.0-release-debugsigned.apk)
  SHA-256: `75c5e8fe1504a05c94eb8a5d55801f433b75fe93afddd5235f86cd6bae704861`
- [Release page and verification reports](https://github.com/abiedadam0077/NOVA-CRAFT/releases/tag/flutter-apk-39339756155-1) · [SHA256SUMS.txt](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39339756155-1/SHA256SUMS.txt) · [apksigner report](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39339756155-1/signature-verification.txt)

CI enabled v1/v2/v3 signing and verified the v1/JAR and v2 schemes, ZIP alignment, package metadata, and downloaded-file checksums. The manifest still declares `minSdk 26`. Large JAR uploads now rebuild against the latest branch head and retry when the active Runner commits status concurrently; Git tree paths retain real filenames. The Runner fix for the observed Playit IPC socket-path failure is included, but a successful live connection still needs to be confirmed after updating and rerunning the user's server repository.

These are AOT release-mode APKs but **debug-signed**, not production-signed. The repository has no production keystore; CI creates an ephemeral debug keystore only for this non-production build. Because that signing key is not a stable release key, Android may refuse to install this APK over an older build signed with another key. Back up anything needed, then uninstall the older app before installing this one; uninstalling removes local app data. The Android emulator smoke workflow was attempted previously but GitHub returned HTTP 403 for workflow dispatch, so installation/launch on a device or emulator is not verified.

## First run

After onboarding and GitHub sign-in, select a repository where the NOVA CRAFT GitHub App has write access, or create a private repository and install the app on it. The repository is selected **before** Playit setup so the agent key can be written directly as the repository's encrypted `PLAYIT_SECRET_KEY` Actions Secret.

Playit is optional. To use it:

1. Create a Playit Agent and copy its `SECRET_KEY`. Save the key in NOVA CRAFT; the app writes it as the repository's encrypted GitHub Actions Secret. Saving it is **not** proof that the Agent has started or connected.
2. Start the server cycle from NOVA CRAFT. The GitHub Runner downloads the pinned official `playitd` binary, verifies its SHA-256, and starts it once with `--secret-path`, a private temporary `--socket-path`, and `--platform-docker`; the secret is kept in a temporary mode-0600 file and is not printed.
3. Wait for the runner status to report **Agent connected**. Only then create a Minecraft Java Tunnel manually in Playit, choose that connected Agent, select TCP, and target `127.0.0.1:25565`. The app/runner never creates a Tunnel.
4. The runner reports **Connection ready** only after the local Minecraft Java Server List Ping succeeds and the public address reported by Playit answers a real game-protocol ping. Missing, unsupported, or unallocated tunnels remain separate states. If the official Agent API does not return an address, enter a known `host:port` manually in Network settings; that override is for the app's direct ping only and does not make the runner claim that its Playit Tunnel is connected.

Playit may be skipped during setup and linked later from Network settings. The screen distinguishes Secret saved, Agent starting/connected/failed, Tunnel state, local server-port status, and externally verified connection. Runner Agent logs are bounded and redacted before publication. The GitHub Actions server cycle is temporary rather than 24/7 hosting.

For a server created by an older app version, stop all of its Actions runs and use **Server settings → Update runner**. This guarded action checks for active runs and updates only generated workflow/helper files; it leaves the world, game properties and GitHub Secrets untouched.

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
