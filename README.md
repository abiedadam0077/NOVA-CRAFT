# NOVA CRAFT

NOVA CRAFT is a native Flutter/Dart Android app for provisioning and managing Minecraft Java and Bedrock servers on GitHub Actions, with Playit.gg as an optional public tunnel. It retains the existing Flutter/Material 3 architecture; it is not a WebView.

- Package: `io.github.abiedadam0077.novacraft`
- Authentication: GitHub App Device Flow; no client secret or private key is embedded in the app.
- Languages: Arabic (RTL) and English (LTR); dark, light and system themes.
- Android: min SDK 26, target SDK 35, compile SDK 36, JDK 17.
- Flutter CI version: 3.35.7.

## Current build and verification

The current implementation is being validated by `.github/workflows/flutter.yml`. That workflow runs static analysis and tests before building an APK, then checks its package/version, verifies its Android signature with `apksigner`, calculates SHA-256, uploads the evidence, publishes a GitHub prerelease, downloads the APK again, and checks the published bytes against the checksum.

No link in this section should be treated as a new verified build until the workflow has completed successfully. See [`docs/REBUILD_REPORT_FINAL.md`](docs/REBUILD_REPORT_FINAL.md) for the current run result, signing status, hash, download link and limitations. [All GitHub releases](https://github.com/abiedadam0077/NOVA-CRAFT/releases).

The repository has no committed production keystore. If the repository's `NOVA_KEYSTORE_BASE64` and `NOVA_KEYSTORE_PASSWORD` secrets are not configured, CI produces a release-mode APK signed with the CI debug key. Such an APK can be used for testing, but it is not a production signing identity and cannot update an installation signed by another key. CI does not generate or replace a release key.

## First run

After onboarding and GitHub sign-in, select a repository where the NOVA CRAFT GitHub App has write access, or create a private repository and install the app on it. The repository is selected **before** Playit setup so the agent key can be written directly as the repository's encrypted `PLAYIT_SECRET_KEY` Actions Secret.

Playit is optional. To use it:

1. Create a Playit Agent and create the needed Tunnel manually in the Playit dashboard. NOVA CRAFT never creates a Tunnel.
2. Enter the Agent `SECRET_KEY`; the app checks it through Playit's official agent endpoint and stores it in GitHub Actions Secrets. The key itself is not displayed in status or logs.
3. Select a matching Tunnel when there are multiple choices. A sole matching Tunnel may be selected automatically; ambiguous or missing IDs are not guessed.
4. The runner reads the address actually reported by the Playit agent. The UI only reports a connection after a real server cycle and game-protocol probe. If Playit has not returned an address, enter a manually verified address or continue without public connectivity.

Playit may be skipped during setup and linked later from Network settings. An unlinked or unavailable Tunnel is shown as unknown/missing/error, not as a successful connection.

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
