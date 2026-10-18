# NOVA CRAFT — Master Implementation Brief
## GitHub Authentication, Playit.gg, Minecraft Server Lifecycle, Backups, UI/UX, and Verified APK Delivery

**Project:** NOVA CRAFT  
**Repository:** https://github.com/abiedadam0077/NOVA-CRAFT

## Mission

Inspect and improve the existing NOVA CRAFT project. Implement the requested first-run setup, secure Playit.gg Agent configuration, manual one-time Tunnel creation with automatic address display when officially supported, Minecraft server management, verified backups, and the repeating five-hour restart cycle.

This is an implementation task, not merely a design proposal. Preserve working functionality and the existing architecture wherever possible. Do not replace the project with a demo or an unrelated implementation.

## Mandatory working rules

1. Audit the current repository and workflows before changing code.
2. Read existing authentication, server creation, start/stop/restart, console, files, network, backup, and Playit code.
3. Inspect the current GitHub Actions runtime limits and the exact Playit Agent version's official documentation.
4. Do not invent API endpoints, OAuth permissions, IP addresses, successful tests, or platform capabilities.
5. Do not mark a feature complete unless it has been implemented and verified.
6. Never expose GitHub tokens, Playit keys, signing keys, or other secrets in logs, commits, artifacts, or ordinary files.
7. Preserve working functionality; avoid unrelated rewrites.
8. Start with a short audit report and a plan. Then implement and test in phases.

---

# 1. Required First-Run Experience

Implement this sequence:

1. Welcome screen.
2. Secure GitHub authentication.
3. Repository selection.
4. Mandatory Playit Agent secret setup.
5. Confirm secret was saved successfully.
6. Server configuration.
7. Create server and launch its GitHub Actions workflow.
8. Dashboard showing real server, workflow, Agent, and tunnel status.

Do not show a falsely “online” dashboard before the relevant checks succeed.

## GitHub authentication

- Use the existing secure architecture if correct; otherwise use an appropriate supported OAuth flow for Android, preferably Authorization Code with PKCE where applicable.
- Never embed a client secret in the APK.
- Request only the permissions required for the selected repository.
- Handle cancellation, expired authorization, denied permissions, and API errors.
- Never log access tokens.
- Verify the user can perform the required repository operations.

## Repository selection

- Load repositories the user can access, including pagination.
- Show owner, name, visibility, and access status.
- Require a valid selected repository before proceeding.
- Persist the repository identity safely.

## Mandatory Playit Agent setup

The user manually creates/selects a Playit Agent on the official Playit website and obtains its secret key. The app provides a secure input field and saves the value as a GitHub Actions repository secret named exactly:

`PLAYIT_SECRET_KEY`

Requirements:
- Password-style input with show/hide and paste support.
- Clear instructions and official Playit link.
- Save/loading/success/error/retry states.
- Verify that GitHub accepted the secret before continuing.
- Use the official GitHub repository-secret API and required encryption procedure.
- Never return or log the saved secret.
- Do not save the secret in repository files, workflow YAML, server configuration, backups, or artifacts.
- Do not ask the user to enter the secret on every server start.

The GitHub secret name is not necessarily the same as the environment variable expected by Playit. Verify the exact Agent version's official documentation and map the secret to the correct runtime environment variable.

---

# 2. Manual Tunnel Creation and Automatic Address Display

**The user will create the Playit Tunnel manually once. The app must then display its actual address and port automatically if Playit provides a supported, documented way to retrieve them.**

Do not try to create tunnels automatically unless an official documented API supports it and the required authorization is verified.

Investigate whether an official Playit API supports reading existing tunnel allocations and addresses.

If supported:
- Implement secure authentication and minimum permissions.
- Retrieve the actual hostname/IP and external port.
- Match the correct tunnel to the selected server and protocol.
- Handle missing tunnels, multiple tunnels, revoked authorization, and API errors.
- Refresh the actual state when requested.

If unsupported:
- Do not scrape private pages or invent undocumented endpoints/scopes.
- Explain the limitation.
- Implement a safe manual-address fallback, with validation and edit capability.
- Do not claim address discovery is automatic when it is not.

Do not require users to create a new Tunnel on every start. Preserve the existing Tunnel and its configuration.

## Java

- Read the actual local Java server port from server configuration; 25565 is only the usual default.
- Display the actual tunnel hostname/IP, external port, local port, TCP protocol, and status.
- Provide copy buttons.

## Bedrock

Bedrock normally requires UDP and, for Java servers, an appropriate Geyser configuration. Do not assume a Java TCP tunnel enables Bedrock.

- Verify server software and Geyser configuration.
- Read the actual configured Bedrock UDP port; 19132 is only the usual default.
- Verify that the selected Playit tunnel supports UDP.
- Apply proxy-protocol settings only when required by the selected tunnel configuration.
- Show Bedrock as connected only after the relevant checks pass.

Use explicit network states:
- Not configured
- Secret missing
- Agent starting
- Agent connected
- Tunnel not created
- Address unavailable
- Local server not listening
- Connection test failed
- Connection ready
- Workflow stopped

Never invent an IP address or show a green connected state based only on the presence of a saved secret.

---

# 3. Minecraft Server Workflow

Preserve the existing server configuration features that are genuinely implemented, such as server name, Minecraft version, supported software, Java runtime, memory settings, server properties, plugins/mods, and Bedrock integration.

Validate all inputs. Do not offer unsupported options.

The workflow should:
1. Validate inputs.
2. Prepare the runtime and server directory.
3. Download the correct server software/version.
4. Apply required configuration and EULA handling.
5. Restore persistent server data when appropriate.
6. Start Minecraft.
7. Start the Playit Agent in the same intended runtime/network environment.
8. Verify both processes.
9. Verify the local server port and Agent connection.
10. Monitor the server.
11. Safely save and stop before planned backup/restart or workflow exit.

Avoid duplicate Minecraft processes and duplicate Agents within one workflow execution.

Do not assume the GitHub Actions runner filesystem persists across separate runs.

---

# 4. Repeating Five-Hour Restart and Backup Cycle

Desired cycle:

**RUN SERVER → SAVE WORLD → STOP SAFELY → CREATE AND VERIFY BACKUP → RESTART AUTOMATICALLY → REPEAT**

The intended interval is five hours. Treat it as a planned maximum interval, not a guarantee of uninterrupted availability for exactly five hours.

Before implementation, verify the applicable GitHub Actions runtime limits, including plan/repository-specific limits and a safety margin. Account for startup and backup duration. If the requested cycle cannot fit safely within the actual limits, report the limitation and implement a safe shorter interval or an explicitly supported external trigger. Do not attempt an uncontrolled workflow chain or bypass platform policies.

## Safe backup sequence

Before planned shutdown:
1. Mark the server as preparing for restart.
2. Issue the server's supported save operation, such as `save-all`, where appropriate.
3. Wait for save completion.
4. Stop Minecraft gracefully using its supported stop command.
5. Confirm the process has exited.
6. Create the backup from a consistent, stopped server state.
7. Validate the archive integrity.
8. Calculate a checksum.
9. Upload to persistent storage.
10. Verify the uploaded backup exists and matches the expected size/checksum where supported.
11. Mark the backup successful only after verification.
12. Restart only according to the documented failure policy.

Never label an unverified archive as a successful backup. Never delete the previous valid backup before the new backup is confirmed.

Exclude secrets, access tokens, Playit keys, keystores, and other credentials from backups.

## Persistent storage and restore

Use the project's existing persistent backup architecture if it is adequate. Otherwise audit the options and document trade-offs before selecting one.

Requirements:
- Persistent backup destination.
- Backup history with timestamps and sizes.
- Integrity verification and checksum.
- Retention policy.
- Safe restore with confirmation.
- Preserve the last known-good backup.
- Recovery from interrupted upload.
- No secrets in archives.

Do not assume GitHub Actions artifacts are permanent. Respect retention limits. Do not use Git history as the default destination for large changing world archives.

## Restart sequence

After a verified backup:
1. Show restart state.
2. Stop old Minecraft and Agent processes cleanly.
3. Confirm processes have exited.
4. Wait a short configurable cooldown.
5. Restore/attach persistent data as required.
6. Start Minecraft.
7. Start Playit Agent.
8. Verify local port and Agent connection.
9. Refresh tunnel status/address.
10. Mark ready only after the necessary checks pass.

Prevent infinite restart loops. Retry with limits and expose useful errors.

A terminated GitHub Actions workflow cannot continue its own loop. Do not claim indefinite automatic restarts unless a supported external trigger is implemented and tested.

---

# 5. Required Screens and Real States

Implement a cohesive set of screens and working navigation:

1. Welcome.
2. GitHub authentication.
3. Repository selection.
4. Playit Agent setup.
5. Secret save confirmation.
6. Server configuration.
7. Server creation progress.
8. Main server dashboard.
9. Console.
10. File manager.
11. Plugins and mods.
12. Network and Playit.
13. Backup and restore.
14. Automatic restart settings.
15. App/server settings.
16. Actionable error and recovery screens.

## Dashboard

Show real values only:
- Server name and actual state.
- Minecraft version/software.
- Real CPU/RAM metrics when available.
- Last verified backup.
- Next planned restart estimate.
- Agent state.
- Tunnel state.
- Workflow running/stopped state.

Clearly distinguish “workflow running” from “server ready”.

## Console

- Actual workflow/server logs.
- Refresh/live updates when available.
- Search/filter where supported.
- Commands only when a secure, working command channel exists.
- Start/stop/restart controls.
- Redact secrets.

## File manager

- Real remote/persistent filesystem, not hardcoded sample files.
- Safe directory navigation.
- Upload/download and text editing for supported file types.
- Correct path validation and directory traversal protection.
- Accurate progress/error states.

## Plugins and mods

- Filter by Minecraft version, server software, and loader.
- Distinguish Java plugins, Java mods, and Bedrock add-ons.
- Validate compatibility before install.
- Use correct directories and supported download sources.
- Provide safe removal/update behavior.
- Back up before destructive changes where appropriate.

## Network screen

- Actual Agent and tunnel status.
- Java TCP address and port.
- Bedrock UDP address and port when configured.
- Local destination ports.
- Copy and refresh actions.
- Manual tunnel setup instructions.
- No fabricated address.

## Backup and restore screen

- Actual backup list and metadata.
- Create backup action.
- Restore action with explicit confirmation.
- Progress and validation status.
- Clear failure handling.

## Restart screen

- Five-hour intended cycle.
- Last verified backup time.
- Next planned restart estimate.
- Current phase.
- Explanation of runtime limits.
- Do not imply persistence beyond workflow termination unless supported.

---

# 6. Visual Design System

Use a premium, polished dark gaming interface.

- Deep navy/black backgrounds.
- Cyan and blue primary accents.
- Restrained violet secondary accents.
- Green only for verified healthy states.
- Red for errors/destructive actions.
- Consistent spacing, typography, card radii, and icons.
- Subtle gradients and glow; avoid excessive effects.
- Minecraft-inspired imagery where it improves clarity.
- Avoid clutter and overly dense layouts.

## Arabic and English

- Proper Arabic RTL and English LTR.
- Mirror directional elements where appropriate.
- Keep IP addresses, ports, commands, paths, and technical identifiers readable.
- Prevent Arabic shaping issues, clipping, text overflow, and mixed-direction rendering problems.
- Preserve exact secret names, filenames, and protocol labels.

## Interaction quality

Every control must have appropriate default, pressed, loading, disabled, success, and error states where relevant.

No inert buttons, fake progress, debug artifacts, yellow underlines, clipped text, overflow errors, or placeholder data presented as real data.

Support small Android screens and different text lengths.

---

# 7. Security

- Keep tokens and secrets out of source code and logs.
- Use secure local storage for sensitive values that must be stored locally.
- Use GitHub Actions Secrets for workflow credentials.
- Use minimum repository permissions.
- Redact credentials from all logs/errors.
- Validate repository identity and all user inputs.
- Prevent shell command injection.
- Prevent path traversal.
- Validate external downloads and file types.
- Never execute uploaded files automatically.
- Never log complete environment variables.
- Handle revoked credentials safely.
- Preserve Android signing credentials and never commit keystores.

---

# 8. Testing and Acceptance Criteria

Do not claim completion until relevant checks have been executed and results reported.

## GitHub/setup
- GitHub login works.
- Cancelled/expired authorization is handled.
- Repository selection and permission checks work.
- `PLAYIT_SECRET_KEY` is saved using the official API.
- Secret value never appears in logs/files.
- Setup state persists safely.

## Playit
- Agent starts with the correct environment variable.
- Agent connects successfully.
- Minecraft and Agent run in the correct runtime/network environment.
- Java tunnel reaches the actual TCP port from outside.
- Bedrock UDP is tested separately if configured.
- Actual address/port appears in the app.
- Missing tunnel and failed connection states are correct.

## Backup/restart
- Test the timer with a shorter development interval.
- Save completes before shutdown.
- Backup archive passes integrity validation.
- Upload is verified.
- Previous good backup is preserved.
- Old processes exit cleanly.
- Restart uses persistent world data.
- No duplicate processes appear.
- Failure cases do not cause destructive cleanup or infinite loops.
- Actual GitHub Actions runtime limits are respected.

## UI/release
- Navigation works on Android.
- Arabic RTL and English LTR are tested.
- No overflow, clipping, or rendering artifacts.
- Loading, empty, error, success, and disconnected states work.
- Existing tests and static analysis are run.
- APK is built using the intended release configuration.
- APK signature is verified.
- SHA-256 checksum is generated.
- APK is uploaded to a valid GitHub Release asset or verified artifact.
- Open the download URL and verify it works before reporting it.

---

# 9. Required Delivery Report

Provide:
1. Modified file list.
2. Summary of implementation.
3. Exact Playit setup behavior.
4. Whether tunnel address retrieval is automatic or requires a fallback.
5. Actual backup and restore design.
6. Actual restart cycle and runtime-limit constraints.
7. Tests executed with results.
8. APK build and signature status.
9. Verified APK download link.
10. APK SHA-256 checksum.
11. Remaining limitations and manual steps.

Do not say “all tests passed” unless the tests actually passed.

## Execution order

Phase A — Audit repository and produce findings.

Phase B — Fix authentication, repository selection, and secure secret saving.

Phase C — Implement and test Playit Agent startup and tunnel address display.

Phase D — Implement and test persistent backup, restore, graceful restart, and the intended five-hour cycle.

Phase E — Complete the UI and all required states without breaking existing functionality.

Phase F — Run tests, verify real connectivity, build APK, verify signature, publish, and report.

Start with Phase A. Do not skip the audit.
