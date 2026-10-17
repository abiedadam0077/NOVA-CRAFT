# NOVA CRAFT — Complete UI/UX Redesign, Feature Expansion & Full-System Repair

## Mission
Repository: https://github.com/abiedadam0077/NOVA-CRAFT

Act as the lead senior mobile engineer, UI/UX designer, backend engineer, DevOps engineer, and QA specialist. Audit the existing project, identify root causes of known bugs, redesign the application, implement the requested features, repair integrations, and test the real workflows. This is not a visual-only redesign. Do not ask for a reference screenshot; use this brief and your own creative judgment.

## 1. Audit Before Editing
Inspect the repository, README, actual framework, architecture, dependencies, Android configuration, GitHub Actions workflows, scripts, APIs, and tests. Trace GitHub authentication, repository secrets, Minecraft downloads/startup, status/log publishing, Playit, and server-file storage. Reproduce and document root causes, then continue with implementation. Preserve working features and user data. Do not replace real functionality with mocks or blindly rewrite the project.

## 2. Visual Identity
Create an original, premium, futuristic Minecraft server control center for NOVA CRAFT:
- Deep navy/near-black blue backgrounds.
- Electric cyan/blue primary accents and violet/purple gradients.
- Accessible green, amber, and red states.
- Refined dark cards, subtle borders, consistent spacing, strong typography, polished icons, restrained neon, and smooth animations.
- Original NOVA CRAFT logo/splash and Minecraft-inspired voxel artwork where useful.
- Reusable components and centralized design tokens.
- Responsive Android layouts, safe-area and keyboard handling, loading skeletons, empty/error/success states, and truthful progress indicators.
- Complete Arabic RTL and English LTR support.
Be creative and distinctive, not a generic template. Avoid clutter, excessive glow, inconsistent typography, blank space, clipped/overlapping content, and broken icons. Remove unintended yellow underline/rendering artifacts by fixing their actual cause; preserve legitimate input indicators.

## 3. User Journey
Implement: branded splash → welcome/onboarding → supported GitHub authorization → guided Playit setup → first-server wizard → genuine installation progress/readiness → main app with exactly five bottom tabs. Before a server exists, prioritize onboarding and server creation instead of an empty dashboard. Remember completed setup steps and provide recovery actions.

## 4. GitHub Authentication and Secrets
Repair GitHub authentication and secret management:
- Use a supported native-app flow, such as a documented device flow where suitable.
- Never embed a GitHub client secret in the APK.
- Request only necessary permissions and explain them.
- Verify repository access and allow repository selection.
- Handle expired authorization, revoked access, insufficient permissions, rate limits, and network failures.
- Retrieve the repository public key, encrypt secret values with the documented algorithm, and submit them using the official GitHub API.
- Confirm the actual API response before showing success; never claim a failed secret was saved.
- Never expose secrets in UI, logs, analytics, error reports, or source control.
- Reconcile secret names with workflows.
Test live when valid credentials are available; otherwise clearly label tests as simulated.

## 5. Playit.gg
Create a guided Playit screen showing real connection, agent, and tunnel status; Java TCP and Bedrock UDP information where supported; verified public address/port; copy, refresh, reconnect, and troubleshooting actions.

Investigate currently supported official APIs before implementing automation. Create agents/tunnels programmatically only if officially supported. Do not invent endpoints or promise unsupported OAuth/automation. If manual approval is necessary, make it short and verify the result where possible.

Store required credentials in GitHub Actions secrets if needed. Never hardcode or log credentials. Do not reuse any credential previously exposed; rotate/revoke it and use a newly generated credential. Do not mark Playit connected merely because a secret or Agent record exists. Verify running agent, active tunnel, protocol, port, and public address. Explain that a tunnel may stop when its GitHub runner stops. Never show fake IPs or hardcoded online states.

## 6. First-Server Wizard and Downloads
Provide server name, Java/Bedrock edition, Minecraft version, supported software/platform, loader where applicable, resource/player settings within real limits, gameplay settings, optional world import/generation, and Playit setup.

For Java, support only verified combinations of software/version, such as Paper, Purpur, Fabric, Forge, and NeoForge where implemented. Use current official metadata/endpoints. Do not offer unsupported combinations. Verify download status, response contents, artifact integrity, and checksum when a trustworthy checksum is available. Never accept an HTML error page as a valid JAR. If an upstream API has changed/retired, use its current official replacement.

For Bedrock, use an appropriate official distribution and verified metadata where permitted. Do not reuse Java download/configuration logic. Distinguish Java TCP from Bedrock UDP.

Show truthful stages: validate configuration, resolve version, download, verify, prepare configuration, EULA confirmation, restore/generate world, start, wait for genuine readiness, and verify networking. Show real progress when available or an honest indeterminate indicator otherwise. Never report success just because a workflow started.

## 7. Repair Server Lifecycle
Investigate workflows, scripts, version resolution, extraction, environment variables, paths, process management, log parsing, timeouts, and status publishing. Fix:
- Invalid downloads and unavailable versions.
- Duplicate/concurrent workflows and conflicting state.
- Runtime mismatches and configuration generation.
- EULA handling after explicit user authorization.
- Safe backup restoration.
- False readiness detection; wait for genuine server readiness.
- Early process exit and exit-status reporting.
- Real status/log publishing.
- Graceful stop/restart and safe backup behavior.
- Safe/idempotent retries where possible.
Do not silently substitute a different Minecraft version. Distinguish harmless outdated-build warnings from real failures. Document GitHub runner duration, temporary storage, shutdown, persistence, and availability limitations. Never promise 24/7 hosting if the infrastructure cannot provide it.

## 8. Exactly Five Primary Tabs
Once a server exists, the bottom navigation must contain exactly:
1. Home — الرئيسية
2. Console — الكونسول
3. Files — الملفات
4. Mods — المودات
5. Server Settings — إعدادات السيرفر

Backups, worlds, networking, and app preferences belong in secondary screens, not extra main tabs.

### Home
Compact view of server name/artwork, edition/software/version, real status (Starting/Online/Stopped/Failed/Unknown), verified address/port, copy action, start/stop/restart, and player count/uptime/memory only when actual data exists. Keep it focused, not a long scrolling dashboard. Confirm disruptive actions and reflect in-progress operations.

### Console
Real logs, timestamps/severity where available, auto-follow, pause/resume, search/filter, clear visible view (without deleting authoritative logs), command input, and loading/disconnected/error states. Explain when commands cannot be sent because the server is stopped or no command channel exists. No fake logs or fake console functionality.

### Files — Server Data Only
Fix the current file manager, which displays only a small subset of server files. Show the selected server's actual filesystem/manifest, not the GitHub repository. For Java, show existing world directories, plugins/, mods/, config/, logs/, server.properties, eula.txt, and other real files. For Bedrock, show actual server/world/config data. Support navigation, file details, safe text config viewing/editing, upload/download where supported, folder creation, rename/delete with confirmation, refresh, and sync status. Never expose workflow files, source code, credentials, or unrelated repository contents. Account for temporary runner storage. When offline, show a timestamped last-synced snapshot and explain its limitations.

### Mods
Adapt to edition and software.

**Java / Modrinth:** use the official Modrinth API. Provide search, categories, pagination, project icon, name, author, description, and metadata only when available. Filter by Minecraft version, loader, and project type. Show details, supported versions, dependencies, install/uninstall, and real progress. Distinguish mods, plugins, datapacks, resource packs, modpacks, etc. Install to the correct folder. Check compatibility with selected version/loader/software; explain incompatibility and show compatible versions. Never install a random version silently. Validate dependencies where feasible, warn about conflicts and restarts, and hide unsupported project types.

**Bedrock / user-provided add-ons:** two sections: “Upload Add-ons — رفع المودات” and “My Add-ons — موداتي”. Allow selecting `.mcaddon` and `.mcpack` from the phone; support `.mcworld` through world import. Show actual name, icon if available, type, install state, and enabled/disabled state. Validate files/manifests, install in correct Bedrock locations, and correctly register/activate behavior/resource packs for the target world. Toggles must change actual configuration, not just UI. Explain restart requirements and support safe uninstall/update where possible. Never imply Java mods are compatible with Bedrock.

## 9. Server Settings
Organize secondary screens for:
- General and valid gameplay settings: name, edition/software/version, game mode, difficulty, max players, PvP, online mode, view/simulation distance, world/spawn, whitelist/operator controls where supported.
- Configuration editor that validates and writes actual files, verifies saved values, and warns about restarts.
- Playit/network status and troubleshooting.
- Backups: manual/scheduled backups, real list, size/time/status, download where supported, validated restore with strong confirmation, retention and storage information when available. Never overwrite an active world with an unvalidated backup.
- Worlds: real list, import/export, selection where supported, backup/restore, confirmed deletion, progress and errors. Support valid Java archives and Bedrock `.mcworld`; prevent path traversal and unsafe extraction.
- App preferences: language, theme, notifications if implemented, GitHub account, privacy information, and app version. Do not add a sixth primary tab.

## 10. Multiple Servers
If supported or safely implementable, allow creating/selecting servers and keep settings, console, files, mods, network, and backups isolated per server. Never mix server data. If the infrastructure cannot run multiple servers simultaneously, explain the actual limitation.

## 11. Backend and Data Integrity
Audit communication among the app, GitHub APIs, Actions, Playit, and Minecraft. Prefer structured status records over fragile parsing of workflow display text. Track server ID, requested edition/software/version, lifecycle status, update time, workflow/execution ID, readiness, non-sensitive error code, verified public address/port, file-manifest timestamp, and operation status as appropriate. Validate incoming data, handle stale/missing status, prevent workflow-run confusion, and recover when the app is reopened. Never claim success before confirmation.

## 12. Errors and Diagnostics
Provide actionable messages and recovery actions for expired GitHub auth, missing permissions, secret failure, unavailable version, download/checksum failure, runtime mismatch, invalid add-on, server exit before readiness, inactive Playit agent/tunnel, missing address, backup failure, and files unavailable after runner termination. Use Retry, Reconnect, Refresh, Review Permissions, Change Version, or View Details as appropriate. Redact secrets.

## 13. Accessibility and Localization
Support Arabic RTL and English LTR across all screens. Handle IPs, ports, paths, code, and Latin server names correctly within Arabic text. Prevent clipping/overlap. Provide contrast, accessible touch targets, labels for icon-only controls, correct keyboard/focus behavior, and consistent date/number/file-size formatting. Use localization resources instead of scattered hardcoded strings.

## 14. Security
Never commit credentials/private keys or embed secrets in the APK. Never log secret values. Use least-privilege permissions, validate inputs and uploaded archives, prevent path traversal, confirm destructive actions, avoid unsafe arbitrary command execution, use safe shell quoting, pin third-party Actions to verified immutable references where feasible, and provide an accurate privacy policy. Do not claim security compliance without evidence.

## 15. Testing and QA
Run existing/new unit tests, UI tests, static analysis, formatting, workflow validation, script tests, API parsing tests, compatibility tests, archive/path tests, and Android debug/release builds.

Test:
1. Fresh onboarding.
2. GitHub login success/failure/retry.
3. Secret creation success when live credentials exist and correct failure reporting otherwise.
4. Valid/invalid versions.
5. Download and artifact verification.
6. Genuine server readiness and startup failure.
7. Start/stop/restart.
8. Playit status and verified address.
9. Server-only file discovery.
10. Modrinth filters, compatibility warnings, correct install paths.
11. Bedrock upload/validation/install/activation.
12. Real configuration save/verification.
13. Backup creation/restore validation.
14. World import/export where supported.
15. Arabic RTL and English LTR.
16. Recovery after app closes during an operation.

Use deterministic mocks for automated tests and real integration tests where credentials/infrastructure are available. Clearly distinguish simulated tests from live tests. Compilation alone does not prove the system works.

## 16. Phased Implementation
A. Audit and root causes.  
B. Fix GitHub, secrets, downloads, lifecycle, status sync, Playit, and file discovery.  
C. Build design system, components, navigation, and localization.  
D. Implement onboarding, GitHub, Playit, and server wizard.  
E. Implement Home, Console, Files, Mods, and Server Settings.  
F. Implement backups, worlds, Bedrock add-ons, multi-server support where feasible, and diagnostics.  
G. Run validation, build artifacts, verify them, and report.

Prioritize correctness and real functionality, but do not leave the UI unfinished. If an external API limitation blocks a feature, explain it and implement the best supported alternative.

## 17. Definition of Done
The work is complete only when:
- The app has a cohesive, original premium design.
- Exactly five primary tabs appear after a server exists.
- Onboarding works.
- GitHub auth/secret failures are handled correctly.
- Downloads use valid sources and verified metadata.
- Startup/readiness reflects reality.
- Playit status/address uses real data.
- Files shows server data, not repository contents.
- Java mods/plugins use compatibility filters and correct paths.
- Bedrock add-ons can be uploaded and installed from device files.
- Settings, backups, and worlds perform real operations.
- Arabic RTL and English LTR work.
- Failures never produce false success.
- Tests/builds pass or remaining failures are documented.
- No secrets are exposed.
- Artifacts and checksums are accurately reported.

## Final Report
Be creative and ambitious with the design, but never sacrifice reliability for appearance. Inspect, identify root causes, implement, redesign, and test. Report:
1. What was broken.
2. What changed.
3. Which features are implemented.
4. Which tests passed.
5. Which live integrations were verified.
6. Remaining external limitations.
7. How to build/install the APK.
8. Where verified artifacts and checksums are available.

Do not fabricate test results, API calls, uptime, tunnel addresses, or completed features. Be transparent about anything not verified.
