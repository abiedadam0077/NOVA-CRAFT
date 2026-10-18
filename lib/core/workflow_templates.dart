import 'models.dart';

/// The GitHub Actions workflow that actually runs a NOVA CRAFT server.
///
/// Design notes (these were real bugs in the previous revision):
/// * `if: env.X` cannot see variables written to `$GITHUB_ENV` by an earlier
///   step, so config values are exposed as step *outputs* instead.
/// * The server gets a five-hour runtime budget inside GitHub's six-hour job
///   limit, leaving up to an hour for startup, graceful shutdown, backup, and
///   dispatching the next cycle.
/// * The world is persisted twice: an Actions cache (fast restore) and a
///   release asset (user visible, survives cache eviction). Both are written
///   only after `save-off` + `save-all flush`, so region files are not zipped
///   while the server writes them.
/// * Server state is published to `nova-craft/status.json` and the live log
///   tail to `nova-craft/live.log`, so the app can show the real state and the
///   real console instead of inferring them from the workflow status.
class WorkflowTemplates {
  const WorkflowTemplates._();

  static const String workflowFile = 'novacraft-server.yml';
  static const String runnerFile = 'nova-craft/runner.sh';

  static String serverWorkflow(String serverId) => _serverWorkflow.replaceAll('__SID__', serverId);

  static const String _serverWorkflow = r'''
name: NOVA CRAFT Server
on:
  workflow_dispatch:
    inputs:
      action:
        description: "start = full runtime cycle, snapshot = archive the saved world only"
        type: choice
        options: [start, snapshot]
        default: start
      restore_tag:
        description: "Optional backup release tag to restore before starting (empty = newest)"
        type: string
        default: ""
concurrency:
  group: novacraft-server-__SID__
  cancel-in-progress: false
permissions:
  contents: write
  actions: write
jobs:
  server:
    runs-on: ubuntu-24.04
    timeout-minutes: 360
    steps:
      - uses: actions/checkout@v4

      - name: Read server configuration
        id: cfg
        run: python3 nova-craft/config.py

      - uses: actions/setup-java@v4
        if: steps.cfg.outputs.edition == 'JAVA'
        with:
          distribution: temurin
          java-version: ${{ steps.cfg.outputs.javamajor }}

      - name: Restore persisted server data
        uses: actions/cache/restore@v4
        with:
          path: ${{ steps.cfg.outputs.data }}
          key: novacraft-data-${{ steps.cfg.outputs.sid }}-${{ github.run_id }}-${{ github.run_attempt }}
          restore-keys: |
            novacraft-data-${{ steps.cfg.outputs.sid }}-

      - name: Run server cycle
        env:
          GH_TOKEN: ${{ github.token }}
          PLAYIT_SECRET_KEY: ${{ secrets.PLAYIT_SECRET_KEY }}
          NOVA_ACTION: ${{ inputs.action }}
          NOVA_RESTORE_TAG: ${{ inputs.restore_tag }}
        run: bash nova-craft/runner.sh

      - name: Save persisted server data
        if: always()
        uses: actions/cache/save@v4
        with:
          path: ${{ steps.cfg.outputs.data }}
          key: novacraft-data-${{ steps.cfg.outputs.sid }}-${{ github.run_id }}-${{ github.run_attempt }}-${{ github.run_number }}
''';

  /// `config.py` turns `server.json` into step outputs without leaking secrets.
  static const String configScript = r'''#!/usr/bin/env python3
"""Expose nova-craft/server.json values as GitHub step outputs."""
import json
import os
import re
import sys

with open("nova-craft/server.json", "r", encoding="utf-8") as handle:
    cfg = json.load(handle)

data_path = cfg.get("dataPath") or "server"
if not isinstance(data_path, str):
    raise SystemExit("unsafe server dataPath")
path_parts = data_path.split("/")
if (data_path.startswith("/") or any(part in ("", ".", "..") or not re.fullmatch(r"[A-Za-z0-9._-]+", part) for part in path_parts)
        or path_parts[0] in (".git", ".github", "nova-craft")):
    raise SystemExit("unsafe server dataPath")
workspace = os.path.realpath(os.getcwd())
resolved_data_path = os.path.realpath(os.path.join(workspace, data_path))
if resolved_data_path != os.path.join(workspace, data_path):
    raise SystemExit("server dataPath cannot traverse a symbolic link")

sid = cfg.get("id")
if not isinstance(sid, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", sid):
    raise SystemExit("unsafe server id")
edition = cfg.get("edition", "JAVA")
software = cfg.get("software", "VANILLA")
if not isinstance(edition, str) or edition.upper() not in ("JAVA", "BEDROCK"):
    raise SystemExit("unsupported server edition")
if not isinstance(software, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,32}", software):
    raise SystemExit("unsafe server software")
edition = edition.upper()
software = software.upper()
try:
    java_major = int(cfg.get("javaMajor", 21))
    memory_mb = int(cfg.get("memoryMb", 4096))
except (TypeError, ValueError):
    raise SystemExit("invalid server runtime settings")
if not 8 <= java_major <= 99 or not 512 <= memory_mb <= 65536:
    raise SystemExit("server runtime settings are outside safe bounds")


def truthy(value):
    return "true" if value else "false"


def write_properties():
    """Regenerate server.properties (and eula.txt) from server.json.

    The Actions cache restores the whole data folder, so values committed in the
    repository could otherwise be overwritten by an older cached copy. Writing
    them again after the restore makes the app's settings authoritative.
    """
    root = data_path
    os.makedirs(root, exist_ok=True)
    bedrock = edition == "BEDROCK"
    if bedrock:
        lines = [
            "server-name=%s" % cfg.get("name", "NOVA CRAFT"),
            "gamemode=%s" % cfg.get("gamemode", "survival"),
            "force-gamemode=false",
            "difficulty=%s" % cfg.get("difficulty", "normal"),
            "allow-cheats=false",
            "max-players=%s" % cfg.get("maxPlayers", 20),
            "online-mode=%s" % truthy(cfg.get("onlineMode", True)),
            "allow-list=%s" % truthy(cfg.get("whiteList", False)),
            "server-port=19132",
            "server-portv6=19133",
            "enable-lan-visibility=false",
            "view-distance=%s" % cfg.get("viewDistance", 10),
            "level-name=Bedrock level",
            "level-seed=%s" % cfg.get("seed", ""),
        ]
    else:
        lines = [
            "#Minecraft server properties (managed by NOVA CRAFT)",
            "level-seed=%s" % cfg.get("seed", ""),
            "gamemode=%s" % cfg.get("gamemode", "survival"),
            "level-name=world",
            "motd=%s" % cfg.get("motd", "A NOVA CRAFT Server"),
            "pvp=%s" % truthy(cfg.get("pvp", True)),
            "difficulty=%s" % cfg.get("difficulty", "normal"),
            "max-players=%s" % cfg.get("maxPlayers", 20),
            "online-mode=%s" % truthy(cfg.get("onlineMode", True)),
            "view-distance=%s" % cfg.get("viewDistance", 10),
            "simulation-distance=%s" % cfg.get("simulationDistance", 10),
            "server-port=25565",
            "white-list=%s" % truthy(cfg.get("whiteList", False)),
            "enforce-whitelist=%s" % truthy(cfg.get("whiteList", False)),
            "allow-nether=true",
            "spawn-animals=true",
            "spawn-monsters=true",
            "spawn-npcs=true",
        ]
    with open(os.path.join(root, "server.properties"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    if not bedrock:
        eula_path = os.path.join(root, "eula.txt")
        if cfg.get("eulaAccepted"):
            with open(eula_path, "w", encoding="utf-8") as handle:
                handle.write("eula=true\n")
        elif os.path.exists(eula_path):
            os.remove(eula_path)


if "--write-props" in sys.argv:
    write_properties()
    sys.exit(0)

out = os.environ["GITHUB_OUTPUT"]
values = {
    "sid": sid,
    "edition": edition,
    "javamajor": str(java_major),
    "data": data_path,
    "software": software,
    "memory": str(memory_mb),
    "eula": "true" if cfg.get("eulaAccepted") else "false",
    "allowcommands": "true" if cfg.get("allowCommands", True) else "false",
    "backupretention": str(max(2, min(30, int(cfg.get("backupRetention", 10))))),
}
with open(out, "a", encoding="utf-8") as handle:
    for key, value in values.items():
        handle.write(f"{key}={value}\n")
print("config:", {k: v for k, v in values.items() if k != "sid"})
''';

  /// The runner itself. Kept out of the YAML so it can be reviewed and updated
  /// independently of the workflow definition.
  static const String runnerScript = r'''#!/usr/bin/env bash
# NOVA CRAFT server runner (GitHub-hosted Ubuntu).
# Responsibilities: restore, download+verify server build, start Playit, run the
# server, publish status/live log, accept queued commands, back up safely, stop.
set -uo pipefail

CFG=nova-craft/server.json
REPO="${GITHUB_REPOSITORY:?}"
ACTION="${NOVA_ACTION:-start}"
REF="${GITHUB_REF_NAME:-main}"
SID="$(python3 -c 'import json;print(json.load(open("nova-craft/server.json"))["id"])')"
DATA="$(python3 -c 'import json;print(json.load(open("nova-craft/server.json")).get("dataPath") or "server")')"
EDITION="$(python3 -c 'import json;print(json.load(open("nova-craft/server.json")).get("edition","JAVA"))')"
SOFTWARE="$(python3 -c 'import json;print(json.load(open("nova-craft/server.json")).get("software","VANILLA").upper())')"
MCV="$(python3 -c 'import json;print(json.load(open("nova-craft/server.json")).get("mcVersion",""))')"
MEMORY="$(python3 -c 'import json;print(int(json.load(open("nova-craft/server.json")).get("memoryMb",4096)))')"
JAVAMAJOR="$(python3 -c 'import json;print(int(json.load(open("nova-craft/server.json")).get("javaMajor",21)))')"
DLURL="$(python3 -c 'import json;print(json.load(open("nova-craft/server.json")).get("downloadUrl",""))')"
DLSHA="$(python3 -c 'import json;print(json.load(open("nova-craft/server.json")).get("downloadSha",""))')"
EULA="$(python3 -c 'import json;print("true" if json.load(open("nova-craft/server.json")).get("eulaAccepted") else "false")')"
PLAYIT_TUNNEL_ID="$(python3 -c 'import json;print(json.load(open("nova-craft/server.json")).get("playitTunnelId",""))')"
AUTORESTART="$(python3 -c 'import json;print("true" if json.load(open("nova-craft/server.json")).get("autoRestart",True) else "false")')"
ALLOW_COMMANDS="$(python3 -c 'import json;print("true" if json.load(open("nova-craft/server.json")).get("allowCommands",True) else "false")')"
BACKUP_RETENTION="$(python3 -c 'import json;print(max(2,min(30,int(json.load(open("nova-craft/server.json")).get("backupRetention",10)))))')"
MAXSEC=18000
JOB_STARTED=$(date +%s)
PHASE=unknown
STATUS_LAST=""
LIVE_LAST=""
PLAYIT_PID=""
PLAYIT_LOG_PATH=""
PLAYIT_SECRET_FILE=""
PLAYIT_CURL_CONFIG=""
PLAYIT_TEMP_DIR=""
PLAYIT_AGENT_STATUS="not_started"
PLAYIT_AGENT_DIAGNOSTIC="agent_not_started"
PLAYIT_AGENT_EXIT_CODE="not_started"
PLAYIT_AGENT_EXIT_CAPTURED=false
PLAYIT_SECRET_STATUS="missing"
SERVER_PORT_STATUS="unknown"
TUNNEL_DIAGNOSTIC="not_started"
FILES_MANIFEST_STATUS="unknown"
FILES_SNAPSHOT_STATUS="unknown"
TUNNEL_LOCAL_IP=""
TUNNEL_LOCAL_PORT=""
GAME_PORT=25565
[ "$EDITION" = "BEDROCK" ] && GAME_PORT=19132
SRV_PID=""
export PLAYIT_AGENT_EXIT_CODE TUNNEL_DIAGNOSTIC FILES_MANIFEST_STATUS FILES_SNAPSHOT_STATUS

cleanup_playit() {
  if [ -n "$PLAYIT_PID" ] && kill -0 "$PLAYIT_PID" 2>/dev/null; then
    kill "$PLAYIT_PID" 2>/dev/null || true
    wait "$PLAYIT_PID" 2>/dev/null || true
  fi
  if [ -n "$PLAYIT_TEMP_DIR" ]; then
    rm -rf -- "$PLAYIT_TEMP_DIR"
  fi
}
trap cleanup_playit EXIT

WORKSPACE_ABS="$(pwd -P)"
if ! python3 - "$DATA" <<'PYDATAPATH'
import re, sys
value = sys.argv[1]
parts = value.split("/")
if not value or value.startswith("/") or any(part in ("", ".", "..") or not re.fullmatch(r"[A-Za-z0-9._-]+", part) for part in parts) or parts[0] in (".git", ".github", "nova-craft"):
    sys.exit(1)
PYDATAPATH
then
  echo "[nova] ERROR server dataPath must be a safe relative path"
  exit 1
fi
DATA_CURSOR="$WORKSPACE_ABS"
IFS='/' read -r -a DATA_PARTS <<< "$DATA"
for segment in "${DATA_PARTS[@]}"; do
  DATA_CURSOR="$DATA_CURSOR/$segment"
  if [ -L "$DATA_CURSOR" ]; then
    echo "[nova] ERROR server dataPath cannot traverse a symbolic link"
    exit 1
  fi
done
mkdir -p -- "$DATA" || { echo "[nova] ERROR could not create server dataPath"; exit 1; }
DATA_ABS="$(cd -- "$DATA" && pwd -P)" || exit 1
if [ "$DATA_ABS" != "$WORKSPACE_ABS/$DATA" ] || [ "$DATA_ABS" = "$WORKSPACE_ABS" ]; then
  echo "[nova] ERROR resolved server dataPath is outside the repository checkout"
  exit 1
fi
cd "$WORKSPACE_ABS" || exit 1

log() { echo "[nova] $*"; }
if [ -n "${PLAYIT_SECRET_KEY:-}" ]; then
  printf '::add-mask::%s\n' "$PLAYIT_SECRET_KEY"
  PLAYIT_SECRET_STATUS=saved
else
  PLAYIT_SECRET_STATUS=missing
fi
export PLAYIT_SECRET_STATUS

# ---------------------------------------------------------------- utilities --

api_content_sha() {
  gh api "repos/$REPO/contents/$1?ref=$REF" --jq .sha 2>/dev/null || echo ""
}

api_content_text() {
  gh api "repos/$REPO/contents/$1?ref=$REF" --jq .content 2>/dev/null | base64 -d 2>/dev/null || true
}

# put_file <path> <text> <message>  — skips the commit when content is unchanged.
put_file() {
  local path="$1" text="$2" message="$3"
  local current sha payload
  current="$(api_content_text "$path")"
  if [ "$current" = "$text" ]; then return 0; fi
  sha="$(api_content_sha "$path")"
  payload="$(mktemp)"
  python3 - "$text" "$message" "$REF" "$sha" > "$payload" <<'PYJSON'
import base64, json, sys
text, message, ref, sha = sys.argv[1:5]
body = {
    "message": message or "nova: update",
    "content": base64.b64encode(text.encode()).decode(),
    "branch": ref or "main",
}
if sha and sha != "null":
    body["sha"] = sha
print(json.dumps(body))
PYJSON
  local api_error detail
  api_error="$(mktemp)"
  if ! gh api -X PUT "repos/$REPO/contents/$path" --input "$payload" > /dev/null 2>"$api_error"; then
    detail="$(tail -n 3 "$api_error" 2>/dev/null | tr '\n' ' ' | sed -E 's/(Authorization:[[:space:]]*Bearer[[:space:]]+)[^[:space:]]+/\1[REDACTED]/Ig; s/(Agent-Key[[:space:]]+)[^[:space:]]+/\1[REDACTED]/Ig; s/[[:xdigit:]]{32,}/[REDACTED]/g' | cut -c1-240)"
    log "WARN GitHub API could not publish $path${detail:+: $detail}"
    rm -f "$api_error" "$payload"
    return 1
  fi
  rm -f "$api_error"
  rm -f "$payload"
  return 0
}

publish_status() {
  local phase="$1" ready="$2" reason="${3:-}" players="${4:-}" pmax="${5:-}" tunnel="${6:-unknown}" tunnel_msg="${7:-}" latency="${8:-}"
  local json
  json="$(python3 - "$phase" "$ready" "$reason" "$players" "$pmax" "$tunnel" "$tunnel_msg" "$latency" "$SRV_PID" "$MCV" "$JOB_STARTED" <<'PY'
import json, os, re, sys, time
phase, ready, reason, players, pmax, tunnel, tmsg, latency, pid, mcv, started = sys.argv[1:12]
def num(v):
    try:
        return int(v)
    except Exception:
        return None
def safe_agent_log_tail():
    path = os.environ.get("PLAYIT_LOG_PATH", "")
    if not path or not os.path.isfile(path):
        return ""
    try:
        with open(path, "rb") as handle:
            handle.seek(max(0, os.fstat(handle.fileno()).st_size - 6000))
            text = handle.read(6000).decode("utf-8", "replace")
    except OSError:
        return ""
    secret = os.environ.get("PLAYIT_SECRET_KEY", "")
    secret_path = os.environ.get("PLAYIT_SECRET_FILE", "")
    if not secret and secret_path:
        try:
            with open(secret_path, "r", encoding="utf-8") as secret_handle:
                secret = secret_handle.read()
        except OSError:
            secret = ""
    if secret:
        text = text.replace(secret, "[REDACTED]")
    text = re.sub(r"(?i)(authorization:\s*agent-key\s+)[^\s\"']+", r"\1[REDACTED]", text)
    text = re.sub(r"(?i)(secret(?:_key)?\s*[:=]\s*)[\"']?[0-9a-f]{16,}[\"']?", r"\1[REDACTED]", text)
    return text
print(json.dumps({
    "schema": 2,
    "serverId": json.load(open("nova-craft/server.json"))["id"],
    "phase": phase,
    "ready": ready == "true",
    "reason": reason,
    "playersOnline": num(players),
    "playersMax": num(pmax),
    "version": mcv,
    "serverPid": num(pid),
    "tunnelStatus": tunnel,
    "tunnelMessage": tmsg,
    "tunnelDiagnostic": os.environ.get("TUNNEL_DIAGNOSTIC", ""),
    "tunnelAddress": os.environ.get("TUNNEL_ADDR", ""),
    "tunnelName": os.environ.get("TUNNEL_NAME", ""),
    "tunnelId": os.environ.get("TUNNEL_ID", ""),
    "tunnelProtocol": os.environ.get("TUNNEL_PROTO", ""),
    "tunnelLocalIp": os.environ.get("TUNNEL_LOCAL_IP", ""),
    "tunnelLocalPort": num(os.environ.get("TUNNEL_LOCAL_PORT", "")),
    "tunnelOfflineReasons": [x for x in [os.environ.get("TUNNEL_ISSUE", "")] if x],
    "agentId": os.environ.get("AGENT_ID", ""),
    "agentStatus": os.environ.get("PLAYIT_AGENT_STATUS", "unknown"),
    "agentDiagnostic": os.environ.get("PLAYIT_AGENT_DIAGNOSTIC", ""),
    "agentExitCode": os.environ.get("PLAYIT_AGENT_EXIT_CODE", "not_started"),
    "playitSecretStatus": os.environ.get("PLAYIT_SECRET_STATUS", "unknown"),
    "serverPortStatus": os.environ.get("SERVER_PORT_STATUS", "unknown"),
    "gamePort": num(os.environ.get("GAME_PORT", "")),
    "agentLogTail": safe_agent_log_tail(),
    "fileManifestStatus": os.environ.get("FILES_MANIFEST_STATUS", "unknown"),
    "fileSnapshotStatus": os.environ.get("FILES_SNAPSHOT_STATUS", "unknown"),
    "latencyMs": num(latency),
    "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "cycleStartedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(float(started))),
    "conclusion": "",
}, ensure_ascii=False, indent=2))
PY
)"
  if [ "$json" != "$STATUS_LAST" ]; then
    STATUS_LAST="$json"
    put_file "nova-craft/status.json" "$json" "nova: status $phase" || true
  fi
}

publish_live() {
  local file="$1"
  [ -f "$file" ] || return 0
  local tail_text
  tail_text="$(tail -n 260 "$file" | tail -c 45000)"
  if [ "$tail_text" != "$LIVE_LAST" ]; then
    LIVE_LAST="$tail_text"
    put_file "nova-craft/live.log" "$tail_text" "nova: live log" || true
  fi
}

publish_files() {
  # The manifest and snapshot are GitHub repository files. The server data used
  # to generate them lives only on this runner while the Actions job is active.
  local files_dir="$WORKSPACE_ABS/nova-craft/files"
  local manifest_path="$files_dir/manifest.json"
  local snapshot_path="$WORKSPACE_ABS/nova-craft/snapshot.json"
  local error_file="$(mktemp)"
  FILES_MANIFEST_STATUS=generation_failed
  FILES_SNAPSHOT_STATUS=generation_failed
  mkdir -p -- "$files_dir" || {
    log "WARN could not create the manifest output directory"
    rm -f "$error_file"
    return 0
  }

  if python3 "$WORKSPACE_ABS/nova-craft/fileops.py" manifest "$DATA_ABS" "$manifest_path" > /dev/null 2>"$error_file"; then
    if put_file "nova-craft/files/manifest.json" "$(cat "$manifest_path")" "nova: file manifest"; then
      FILES_MANIFEST_STATUS=published
    else
      FILES_MANIFEST_STATUS=publish_failed
      log "WARN generated file manifest could not be published to GitHub Contents"
    fi
  else
    local detail
    detail="$(tail -n 4 "$error_file" 2>/dev/null | tr '\n' ' ' | cut -c1-320)"
    log "WARN manifest generation failed${detail:+: $detail}"
  fi

  : > "$error_file"
  if python3 "$WORKSPACE_ABS/nova-craft/fileops.py" snapshot "$DATA_ABS" "$snapshot_path" > /dev/null 2>"$error_file"; then
    if put_file "nova-craft/snapshot.json" "$(cat "$snapshot_path")" "nova: config snapshot"; then
      FILES_SNAPSHOT_STATUS=published
    else
      FILES_SNAPSHOT_STATUS=publish_failed
      log "WARN generated editable snapshot could not be published to GitHub Contents"
    fi
  else
    local detail
    detail="$(tail -n 4 "$error_file" 2>/dev/null | tr '\n' ' ' | cut -c1-320)"
    log "WARN config snapshot generation failed${detail:+: $detail}"
  fi
  rm -f "$error_file"
}

# File operations requested from the app. Applied immediately while a cycle is
# running, so the Files tab is not limited to "next start".
apply_file_request() {
  local sha payload_text
  sha="$(api_content_sha "nova-craft/files/request.json")"
  [ -n "$sha" ] || return 0
  payload_text="$(gh api "repos/$REPO/contents/nova-craft/files/request.json?ref=$REF" --jq .content 2>/dev/null | base64 -d 2>/dev/null)"
  [ -n "$payload_text" ] || return 0
  local req_id
  printf '%s' "$payload_text" > /tmp/nova-req.json
  req_id="$(python3 -c 'import json;print(json.load(open("/tmp/nova-req.json")).get("id",""))' 2>/dev/null || echo "")"
  [ -n "$req_id" ] || { echo "WARN: file request without id"; return 0; }
  if [ "$req_id" = "$LAST_FILE_REQ" ]; then return 0; fi
  LAST_FILE_REQ="$req_id"
  log "file request $req_id"
  python3 nova-craft/fileops.py request "$DATA_ABS" /tmp/nova-req.json /tmp/nova-res.json > /dev/null 2>&1 || true
  if [ -f /tmp/nova-res.json ]; then
    put_file "nova-craft/files/response.json" "$(cat /tmp/nova-res.json)" "nova: file response" || true
  fi
  gh api -X DELETE "repos/$REPO/contents/nova-craft/files/request.json" \
    -f message="nova: file request consumed" -f sha="$sha" -f branch="$REF" > /dev/null 2>&1 || true
  publish_files
}

publish_cycle_end() {
  local conclusion="$1" reason="$2"
  local json
  json="$(python3 - "$conclusion" "$reason" "$MCV" "$JOB_STARTED" <<'PY'
import json, os, re, sys, time
conclusion, reason, mcv, started = sys.argv[1:5]
def safe_agent_log_tail():
    path = os.environ.get("PLAYIT_LOG_PATH", "")
    if not path or not os.path.isfile(path):
        return ""
    try:
        with open(path, "rb") as handle:
            handle.seek(max(0, os.fstat(handle.fileno()).st_size - 6000))
            text = handle.read(6000).decode("utf-8", "replace")
    except OSError:
        return ""
    secret = os.environ.get("PLAYIT_SECRET_KEY", "")
    secret_path = os.environ.get("PLAYIT_SECRET_FILE", "")
    if not secret and secret_path:
        try:
            with open(secret_path, "r", encoding="utf-8") as secret_handle:
                secret = secret_handle.read()
        except OSError:
            secret = ""
    if secret:
        text = text.replace(secret, "[REDACTED]")
    text = re.sub(r"(?i)(authorization:\s*agent-key\s+)[^\s\"']+", r"\1[REDACTED]", text)
    text = re.sub(r"(?i)(secret(?:_key)?\s*[:=]\s*)[\"']?[0-9a-f]{16,}[\"']?", r"\1[REDACTED]", text)
    return text
print(json.dumps({
    "schema": 2,
    "serverId": json.load(open("nova-craft/server.json"))["id"],
    "phase": "stopped" if conclusion == "success" else "failed",
    "ready": False,
    "reason": reason,
    "conclusion": conclusion,
    "version": mcv,
    "tunnelStatus": os.environ.get("TUNNEL_STATE", "unknown"),
    "tunnelMessage": os.environ.get("TUNNEL_MSG", ""),
    "tunnelDiagnostic": os.environ.get("TUNNEL_DIAGNOSTIC", ""),
    "tunnelAddress": os.environ.get("TUNNEL_ADDR", ""),
    "tunnelName": os.environ.get("TUNNEL_NAME", ""),
    "tunnelId": os.environ.get("TUNNEL_ID", ""),
    "tunnelProtocol": os.environ.get("TUNNEL_PROTO", ""),
    "tunnelLocalIp": os.environ.get("TUNNEL_LOCAL_IP", ""),
    "tunnelLocalPort": int(os.environ.get("TUNNEL_LOCAL_PORT", "0") or 0) or None,
    "agentId": os.environ.get("AGENT_ID", ""),
    "agentStatus": os.environ.get("PLAYIT_AGENT_STATUS", "unknown"),
    "agentDiagnostic": os.environ.get("PLAYIT_AGENT_DIAGNOSTIC", ""),
    "agentExitCode": os.environ.get("PLAYIT_AGENT_EXIT_CODE", "not_started"),
    "playitSecretStatus": os.environ.get("PLAYIT_SECRET_STATUS", "unknown"),
    "serverPortStatus": os.environ.get("SERVER_PORT_STATUS", "unknown"),
    "gamePort": int(os.environ.get("GAME_PORT", "0") or 0) or None,
    "agentLogTail": safe_agent_log_tail(),
    "fileManifestStatus": os.environ.get("FILES_MANIFEST_STATUS", "unknown"),
    "fileSnapshotStatus": os.environ.get("FILES_SNAPSHOT_STATUS", "unknown"),
    "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "cycleStartedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(float(started))),
}, ensure_ascii=False, indent=2))
PY
)"
  put_file "nova-craft/status.json" "$json" "nova: cycle $conclusion" || true
}

verify_hash() {
  local file="$1" hash="$2"
  if [ -z "$hash" ]; then log "no checksum published for $file (skipping verification)"; return 0; fi
  local len=${#hash}
  if [ "$len" -eq 64 ]; then echo "$hash  $file" | sha256sum -c - || return 1
  elif [ "$len" -eq 40 ]; then echo "$hash  $file" | sha1sum -c - || return 1
  elif [ "$len" -eq 32 ]; then echo "$hash  $file" | md5sum -c - || return 1
  else log "unknown checksum length ($len); skipping verification"; ci=false; return 0
  fi
}

download() {
  local url="$1" out="$2" hash="$3"
  local tmp="${out}.part"
  rm -f "$tmp"
  log "downloading $url"
  curl -fL --retry 4 --retry-all-errors --connect-timeout 20 -o "$tmp" "$url" || return 1
  [ -s "$tmp" ] || { log "ERROR empty download"; rm -f "$tmp"; return 1; }
  if ! verify_hash "$tmp" "$hash"; then
    log "ERROR checksum mismatch for $out"
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$out"
}

wait_for_port() {
  local host="$1" port="$2" timeout="$3"
  python3 - "$host" "$port" "$timeout" <<'PY'
import socket, sys, time
host, port, timeout = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
deadline = time.time() + timeout
while time.time() < deadline:
    try:
        with socket.create_connection((host, port), timeout=2):
            sys.exit(0)
    except OSError:
        time.sleep(1)
sys.exit(1)
PY
}

probe_tunnel() {
  # The helper requires an actual Java SLP/TCP or Bedrock RakNet/UDP reply.
  # External probes also require the one running official Playit Agent.
  local address="$1" require_agent="${2:-true}"
  [ -n "$address" ] || return 1
  if [ "$require_agent" = "true" ]; then
    [ -n "$PLAYIT_PID" ] || return 1
    kill -0 "$PLAYIT_PID" 2>/dev/null || return 1
  fi
  python3 "$WORKSPACE_ABS/nova-craft/playit.py" probe "$address" "$EDITION"
}

# -------------------------------------------------------------- validation --

if [ "$EDITION" = "JAVA" ] && [ "$ACTION" = "start" ] && [ "$EULA" != "true" ]; then
  log "ERROR Minecraft EULA was not accepted in the app; refusing to start."
  publish_cycle_end failure "eula-not-accepted"
  exit 1
fi

if [ "$EDITION" = "JAVA" ] && [ -z "$DLURL" ]; then
  log "ERROR server.json has no download URL; re-save the server in the app."
  publish_cycle_end failure "missing-download-url"
  exit 1
fi

# ---------------------------------------------------------------- restore --

mkdir -p nova-craft
INCOMING=nova-craft/import
REQUESTED_RESTORE_TAG="${NOVA_RESTORE_TAG:-}"
RESTORE_TAG=""
if [ "$ACTION" = "snapshot" ]; then
  if [ -n "$REQUESTED_RESTORE_TAG" ]; then
    log "ERROR snapshot actions cannot include a restore tag"
    publish_cycle_end failure "invalid-restore-tag"
    exit 1
  fi
else
  if [ -n "$REQUESTED_RESTORE_TAG" ]; then
    case "$REQUESTED_RESTORE_TAG" in
      "backup-$SID-"[A-Za-z0-9_-][A-Za-z0-9_-]*) ;;
      *)
        log "ERROR the requested backup tag does not belong to this server"
        publish_cycle_end failure "invalid-restore-tag"
        exit 1
        ;;
    esac
  else
    RELEASE_LIST="/tmp/nova-backup-releases.json"
    if gh api "repos/$REPO/releases?per_page=100" > "$RELEASE_LIST" 2>/dev/null; then
      REQUESTED_RESTORE_TAG="$(python3 - "$RELEASE_LIST" "$SID" <<'PYLATEST'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    releases = json.load(handle)
prefix = "backup-%s-" % sys.argv[2]
backups = []
for release in releases:
    if not isinstance(release, dict) or release.get("draft"):
        continue
    if not str(release.get("tag_name", "")).startswith(prefix):
        continue
    if "NOVA_CRAFT_BACKUP_VERIFIED" not in str(release.get("body", "")):
        continue
    assets = {asset.get("name") for asset in (release.get("assets") or []) if isinstance(asset, dict)}
    if {"world-backup.zip", "world-backup.sha256"} <= assets:
        backups.append(release)
backups.sort(key=lambda release: str(release.get("created_at", "")), reverse=True)
if backups:
    print(backups[0].get("tag_name", ""))
PYLATEST
      )"
    else
      log "WARN could not list verified backups; using the cached world"
    fi
  fi
fi

restore_backup_archive() {
  python3 - "$1" "$DATA_ABS" "$EDITION" <<'PYRESTORE'
import os, shutil, stat, sys, zipfile
archive_path, root, edition = sys.argv[1:]
world_roots = {"worlds"} if edition == "BEDROCK" else {"world", "world_nether", "world_the_end"}
shared = ({"server.properties", "allowlist.json", "permissions.json"} if edition == "BEDROCK" else
          {"server.properties", "whitelist.json", "banned-players.json", "banned-ips.json", "ops.json"})
stage = os.path.join(root, ".nova-restore-stage")
if os.path.exists(stage):
    if os.path.islink(stage):
        raise SystemExit("restore staging path is a symlink")
    shutil.rmtree(stage)
os.makedirs(stage)
try:
    with zipfile.ZipFile(archive_path, "r") as archive:
        infos = archive.infolist()
        if not infos or len(infos) > 100000:
            raise ValueError("empty or oversized backup manifest")
        accepted = []
        seen = set()
        expanded_size = 0
        max_total_size = 8 * 1024 * 1024 * 1024
        max_file_size = 4 * 1024 * 1024 * 1024
        for info in infos:
            name = info.filename.replace("\\", "/")
            clean_name = name.rstrip("/")
            if clean_name in seen:
                raise ValueError("duplicate archive path")
            seen.add(clean_name)
            if info.file_size < 0 or info.file_size > max_file_size:
                raise ValueError("backup file exceeds the restore size limit")
            expanded_size += info.file_size
            if expanded_size > max_total_size:
                raise ValueError("backup exceeds the restore size limit")
            parts = clean_name.split("/")
            if name.startswith("/") or not clean_name or any(part in ("", ".", "..") for part in parts):
                raise ValueError("unsafe archive path")
            first = parts[0]
            if first not in world_roots and not (len(parts) == 1 and first in shared):
                raise ValueError("unexpected path in backup")
            mode = (info.external_attr >> 16) & 0xffff
            if stat.S_ISLNK(mode):
                raise ValueError("symlink in backup")
            if info.is_dir():
                continue
            if mode and not stat.S_ISREG(mode):
                raise ValueError("non-regular file in backup")
            accepted.append((info, name))
        if not accepted:
            raise ValueError("backup has no files")
        if archive.testzip() is not None:
            raise ValueError("backup CRC verification failed")
        for info, name in accepted:
            target = os.path.realpath(os.path.join(stage, *name.rstrip("/").split("/")))
            if os.path.commonpath((os.path.realpath(stage), target)) != os.path.realpath(stage):
                raise ValueError("archive path escaped staging root")
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with archive.open(info, "r") as source, open(target, "wb") as destination:
                shutil.copyfileobj(source, destination)
        # Only after the complete archive is checked and staged do we replace
        # the existing world folders and shared files.
        world_data_found = False
        for world_root in world_roots:
            staged_world = os.path.join(stage, world_root)
            if os.path.isdir(staged_world):
                for _, _, files in os.walk(staged_world):
                    if files:
                        world_data_found = True
                        break
            if world_data_found:
                break
        if not world_data_found:
            raise ValueError("backup contains no world data")
        previous_root = os.path.join(stage, ".previous")
        os.makedirs(previous_root)
        moved_old = []
        installed_new = []
        try:
            for rel in world_roots:
                target = os.path.join(root, rel)
                staged = os.path.join(stage, rel)
                if not os.path.isdir(staged):
                    continue
                if os.path.lexists(target):
                    if os.path.islink(target) or not os.path.isdir(target):
                        raise ValueError("unsafe existing world path")
                    previous = os.path.join(previous_root, rel)
                    os.makedirs(os.path.dirname(previous), exist_ok=True)
                    os.replace(target, previous)
                    moved_old.append((target, previous))
                os.replace(staged, target)
                installed_new.append(target)
            for rel in shared:
                staged = os.path.join(stage, rel)
                if not os.path.isfile(staged):
                    continue
                target = os.path.join(root, rel)
                if os.path.lexists(target):
                    if os.path.isdir(target) and not os.path.islink(target):
                        raise ValueError("unsafe existing shared path")
                    previous = os.path.join(previous_root, rel)
                    os.makedirs(os.path.dirname(previous), exist_ok=True)
                    os.replace(target, previous)
                    moved_old.append((target, previous))
                os.replace(staged, target)
                installed_new.append(target)
        except Exception:
            for target in reversed(installed_new):
                if not os.path.lexists(target):
                    continue
                if os.path.isdir(target) and not os.path.islink(target):
                    shutil.rmtree(target)
                else:
                    os.unlink(target)
            for target, previous in reversed(moved_old):
                if os.path.lexists(previous):
                    os.makedirs(os.path.dirname(target), exist_ok=True)
                    os.replace(previous, target)
            raise
finally:
    if os.path.isdir(stage) and not os.path.islink(stage):
        shutil.rmtree(stage, ignore_errors=True)
print("verified backup extracted safely")
PYRESTORE
}

if [ -n "$REQUESTED_RESTORE_TAG" ]; then
  log "checking backup release $REQUESTED_RESTORE_TAG"
  TMPD="$(mktemp -d)"
  if gh release download "$REQUESTED_RESTORE_TAG" --repo "$REPO" --pattern "world-backup.zip" --dir "$TMPD" 2>/dev/null \
      && gh release download "$REQUESTED_RESTORE_TAG" --repo "$REPO" --pattern "world-backup.sha256" --dir "$TMPD" 2>/dev/null \
      && (cd "$TMPD" && sha256sum -c world-backup.sha256) \
      && restore_backup_archive "$TMPD/world-backup.zip"; then
    RESTORE_TAG="$REQUESTED_RESTORE_TAG"
    log "restored verified backup $RESTORE_TAG"
  else
    rm -rf "$TMPD"
    log "ERROR backup could not be verified/restored; refusing to start from an older cached world"
    publish_cycle_end failure "backup-restore-failed"
    exit 1
  fi
  rm -rf "$TMPD"
fi

# Settings from the app always win over the cached copy.
python3 nova-craft/config.py --write-props || log "WARN could not rewrite server.properties"

# Small config edits made in the app while the server was stopped live in the
# repository snapshot; they must win over the restored cache too.
if [ -f nova-craft/snapshot.json ]; then
  python3 nova-craft/fileops.py apply-snapshot "$DATA_ABS" nova-craft/snapshot.json \
    || log "WARN could not apply the repository snapshot"
fi

# Packages uploaded from the phone (worlds, jars, add-ons) are copied in here.
if [ -d nova-craft/uploads ]; then
  for f in nova-craft/uploads/*; do
    [ -f "$f" ] || continue
    case "$f" in
      *.gitkeep|*.json) continue ;;
    esac
    log "applying upload $(basename "$f")"
    cp -f "$f" "$DATA_ABS/$(basename "$f")" || log "WARN upload copy failed"
  done
fi

# Add-on packages are installed before the server starts so toggles are real.
if [ -f nova-craft/addons/state.json ]; then
  python3 nova-craft/fileops.py addons "$DATA_ABS" nova-craft/addons nova-craft/addons/state.json /tmp/nova-addons.json \
    && cp /tmp/nova-addons.json nova-craft/addons/result.json || log "WARN add-on install failed"
fi

if [ -f "$INCOMING/world.zip" ]; then
  log "applying imported world"
  WORLD_NAME="$(python3 -c 'import json;d=json.load(open("nova-craft/import/world.json"));print(d.get("name") or "Imported world")' 2>/dev/null || echo "Imported world")"
  if python3 nova-craft/fileops.py import "$DATA_ABS" "$INCOMING/world.zip" "$WORLD_NAME" /tmp/nova-import.json; then
    cp /tmp/nova-import.json nova-craft/import/result.json || true
    SHA="$(api_content_sha "$INCOMING/world.zip")"
    if [ -n "$SHA" ]; then
      gh api -X DELETE "repos/$REPO/contents/$INCOMING/world.zip" -f message="nova: import applied" -f sha="$SHA" -f branch="$REF" > /dev/null 2>&1 || true
    fi
  else
    cp /tmp/nova-import.json nova-craft/import/result.json || true
    log "WARN imported world was rejected (see nova-craft/import/result.json)"
  fi
fi

# ------------------------------------------------------------------- EULA --

if [ "$EDITION" = "JAVA" ]; then
  if [ "$EULA" = "true" ]; then echo "eula=true" > "$DATA_ABS/eula.txt"; fi
fi

# ---------------------------------------------------------------- snapshot --

prune_backups() {
  local listing="/tmp/nova-backup-releases.json"
  local obsolete="/tmp/nova-backup-prune.txt"
  gh api "repos/$REPO/releases?per_page=100" > "$listing" 2>/dev/null || {
    log "WARN could not list releases for backup retention"
    return 0
  }
  if ! python3 - "$listing" "$SID" "$BACKUP_RETENTION" > "$obsolete" <<'PYPRUNE'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    releases = json.load(handle)
prefix = "backup-%s-" % sys.argv[2]
keep = max(2, min(30, int(sys.argv[3])))
verified = []
for release in releases:
    if not isinstance(release, dict) or release.get("draft"):
        continue
    if not str(release.get("tag_name", "")).startswith(prefix):
        continue
    if "NOVA_CRAFT_BACKUP_VERIFIED" not in str(release.get("body", "")):
        continue
    assets = {asset.get("name") for asset in (release.get("assets") or []) if isinstance(asset, dict)}
    if {"world-backup.zip", "world-backup.sha256"} <= assets:
        verified.append(release)
verified.sort(key=lambda release: str(release.get("created_at", "")), reverse=True)
for release in verified[keep:]:
    print(release.get("tag_name", ""))
PYPRUNE
  then
    log "WARN could not evaluate backup retention safely"
    return 0
  fi
  while IFS= read -r old_tag; do
    [ -n "$old_tag" ] || continue
    if gh release delete "$old_tag" --repo "$REPO" --yes --cleanup-tag; then
      log "pruned old verified backup $old_tag"
    else
      log "WARN failed to prune old backup $old_tag"
    fi
  done < "$obsolete"
}

backup_now() {
  local phase_label="$1"
  local ts tag verify_dir work_dir archive_size
  ts="$(date -u +%Y%m%dT%H%M%S%NZ)"
  tag="backup-$SID-$ts"
  # Old versions placed the archive in the cached server directory, doubling
  # cache size on every cycle. Keep archives only in ephemeral runner storage.
  rm -f "$DATA_ABS/world-backup.zip" "$DATA_ABS/world-backup.sha256"
  work_dir="$(mktemp -d)"
  if ! python3 - "$DATA_ABS" "$EDITION" "$work_dir/world-backup.zip" "$work_dir/world-backup.sha256" <<'PYBACKUP'
import hashlib, os, sys, zipfile
root, edition, archive_path, checksum_path = sys.argv[1:]
paths = (["worlds", "server.properties", "allowlist.json", "permissions.json"]
         if edition == "BEDROCK" else
         ["world", "world_nether", "world_the_end", "server.properties",
          "whitelist.json", "banned-players.json", "banned-ips.json", "ops.json"])
world_paths = ["worlds"] if edition == "BEDROCK" else ["world", "world_nether", "world_the_end"]
world_files = []
for rel in world_paths:
    full = os.path.join(root, rel)
    if os.path.isdir(full) and not os.path.islink(full):
        for current, dirs, files in os.walk(full, followlinks=False):
            if any(os.path.islink(os.path.join(current, name)) for name in dirs + files):
                raise SystemExit("refusing to archive a symlink in world data")
            world_files.extend(os.path.join(current, name) for name in files)
if not world_files:
    raise SystemExit("no world data found; refusing to publish an empty backup")
count = 0
with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as archive:
    for rel in paths:
        full = os.path.join(root, rel)
        if not os.path.exists(full):
            continue
        if os.path.islink(full):
            raise SystemExit("refusing to archive a symlink")
        if os.path.isdir(full):
            for current, dirs, files in os.walk(full, followlinks=False):
                dirs.sort(); files.sort()
                if any(os.path.islink(os.path.join(current, name)) for name in dirs + files):
                    raise SystemExit("refusing to archive a symlink")
                for name in files:
                    source = os.path.join(current, name)
                    archive.write(source, os.path.relpath(source, root))
                    count += 1
        else:
            archive.write(full, rel)
            count += 1
if count == 0:
    raise SystemExit("backup archive contains no files")
with zipfile.ZipFile(archive_path, "r") as archive:
    corrupt = archive.testzip()
    if corrupt is not None:
        raise SystemExit("archive verification failed at %s" % corrupt)
digest = hashlib.sha256()
with open(archive_path, "rb") as handle:
    for block in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(block)
with open(checksum_path, "w", encoding="ascii") as handle:
    handle.write("%s  world-backup.zip\n" % digest.hexdigest())
print("verified %d files (%d bytes)" % (count, os.path.getsize(archive_path)))
PYBACKUP
  then
    rm -rf "$work_dir"
    log "ERROR world backup creation or local verification failed"
    return 1
  fi
  archive_size="$(stat -c '%s' "$work_dir/world-backup.zip" 2>/dev/null || echo 0)"
  if [ "$archive_size" -gt 2147483648 ]; then
    rm -rf "$work_dir"
    log "ERROR backup exceeds GitHub's 2 GiB release-asset limit; old backups were preserved"
    return 1
  fi
  if ! gh release create "$tag" "$work_dir/world-backup.zip" "$work_dir/world-backup.sha256" \
        --repo "$REPO" --title "Backup $ts" \
        --notes "NOVA CRAFT $phase_label backup (restored: ${RESTORE_TAG:-cache})"; then
    log "WARN release create failed; attempting upload to an existing tag"
    if ! gh release upload "$tag" "$work_dir/world-backup.zip" "$work_dir/world-backup.sha256" \
        --repo "$REPO" --clobber; then
      rm -rf "$work_dir"
      return 1
    fi
  fi
  verify_dir="$(mktemp -d)"
  if ! gh release download "$tag" --repo "$REPO" --pattern "world-backup.zip" --pattern "world-backup.sha256" --dir "$verify_dir"; then
    rm -rf "$work_dir" "$verify_dir"
    log "ERROR could not download the published backup for verification"
    return 1
  fi
  if ! (cd "$verify_dir" && sha256sum -c world-backup.sha256 && python3 - <<'PYVERIFY'
import sys, zipfile
with zipfile.ZipFile("world-backup.zip", "r") as archive:
    sys.exit(0 if archive.testzip() is None and archive.namelist() else 1)
PYVERIFY
  ); then
    rm -rf "$work_dir" "$verify_dir"
    log "ERROR published backup failed checksum or archive verification"
    return 1
  fi
  if ! gh release edit "$tag" --repo "$REPO" \
      --notes "NOVA_CRAFT_BACKUP_VERIFIED — NOVA CRAFT re-downloaded this backup and verified its SHA-256 and ZIP CRC."; then
    log "WARN backup bytes verified, but could not write the verification marker to the release notes"
  fi
  rm -rf "$work_dir" "$verify_dir"
  log "backup published and verified $tag"
  prune_backups
  return 0
}

if [ "$ACTION" = "snapshot" ]; then
  if backup_now "snapshot"; then
    publish_cycle_end success "snapshot"
    exit 0
  fi
  publish_cycle_end failure "snapshot-failed"
  exit 1
fi

# ------------------------------------------------------------- Downloads ---

cd "$DATA_ABS" || exit 1
if [ "$EDITION" = "JAVA" ]; then
  # Fabric launchers are re-downloaded per loader, so only cache immutable jars.
  if [ -f server.jar ] && [ -n "$DLSHA" ]; then
    if verify_hash server.jar "$DLSHA" 2>/dev/null; then
      log "server.jar already present and verified"
    else
      log "cached server.jar does not match the pinned checksum; re-downloading"
      rm -f server.jar
      download "$DLURL" server.jar "$DLSHA" || { publish_cycle_end failure "download-failed"; exit 1; }
    fi
  else
    download "$DLURL" server.jar "$DLSHA" || { publish_cycle_end failure "download-failed"; exit 1; }
  fi
else
  # Bedrock updates are mandatory for clients, so the installed build is tied
  # to the resolved URL. A new URL replaces the old server instead of keeping a
  # stale bedrock_server forever.
  BURL="$DLURL"
  if [ -z "$BURL" ] || [ "$BURL" = "https://www.minecraft.net/en-us/download/server/bedrock" ]; then
    BURL="$(curl -sL -A "Mozilla/5.0" https://www.minecraft.net/en-us/download/server/bedrock \
      | grep -oE "https://www\.minecraft\.net/bedrockdedicatedserver/bin-linux/[^\"']+\.zip" | head -1)"
  fi
  if [ -z "$BURL" ]; then
    if [ -f bedrock_server ]; then
      log "WARN could not resolve a new Bedrock build; using the cached server"
    else
      log "ERROR could not resolve the Bedrock download URL"
      publish_cycle_end failure "bedrock-download-url"
      exit 1
    fi
  else
    PREV=""
    [ -f bedrock.url ] && PREV="$(cat bedrock.url 2>/dev/null || true)"
    if [ ! -f bedrock_server ] || [ "$PREV" != "$BURL" ]; then
      download "$BURL" bedrock.zip "" || { publish_cycle_end failure "download-failed"; exit 1; }
      unzip -o -q bedrock.zip || { publish_cycle_end failure "bedrock-unzip"; exit 1; }
      chmod +x bedrock_server
      rm -f bedrock.zip
      printf '%s' "$BURL" > bedrock.url
      log "bedrock build installed from $BURL"
    else
      log "bedrock build already current"
    fi
  fi
fi
cd "$WORKSPACE_ABS" || exit 1

# ------------------------------------------------------------ Playit agent --

playit_api() {
  local endpoint="$1" payload="$2" error_path="$PLAYIT_TEMP_DIR/api.err"
  PLAYIT_API_HTTP_STATUS=""
  PLAYIT_API_EXIT_CODE=0
  PLAYIT_API_ERROR=""
  if PLAYIT_API_HTTP_STATUS="$(curl -sS --connect-timeout 10 --max-time 25 \
      --config "$PLAYIT_CURL_CONFIG" -X POST "https://api.playit.gg$endpoint" \
      -H "Content-Type: application/json" -d "$payload" \
      -o "$PLAYIT_TEMP_DIR/rundata.json" -w '%{http_code}' 2>"$error_path")"; then
    return 0
  else
    PLAYIT_API_EXIT_CODE=$?
  fi
  PLAYIT_API_ERROR="$(python3 - "$error_path" "$PLAYIT_SECRET_FILE" <<'PYAPIERR'
import re, sys
try:
    text = open(sys.argv[1], encoding="utf-8", errors="replace").read()[-1200:].replace("\n", " ").replace("\r", " ").strip()
except OSError:
    text = ""
try:
    secret = open(sys.argv[2], encoding="utf-8").read()
except OSError:
    secret = ""
if secret:
    text = text.replace(secret, "[REDACTED]")
text = re.sub(r"(?i)(authorization:\s*agent-key\s+)[^\s\"']+", r"\1[REDACTED]", text)
print(text[:320])
PYAPIERR
  )"
  log "PLAYIT_API_TRANSPORT_ERROR exit=$PLAYIT_API_EXIT_CODE${PLAYIT_API_ERROR:+ detail=$PLAYIT_API_ERROR}"
  return 1
}

refresh_tunnel() {
  rm -f "$PLAYIT_TEMP_DIR/rundata.json" "$PLAYIT_TEMP_DIR/tunnel.env"
  if ! playit_api /v1/agents/rundata '{}'; then
    TUNNEL_STATE=error
    TUNNEL_DIAGNOSTIC=rundata_network_error
    TUNNEL_MSG="Playit rundata transport failed (curl exit $PLAYIT_API_EXIT_CODE)${PLAYIT_API_ERROR:+: $PLAYIT_API_ERROR}"
    return 1
  fi
  case "$PLAYIT_API_HTTP_STATUS" in
    2??) ;;
    401)
      TUNNEL_STATE=error
      TUNNEL_DIAGNOSTIC=rundata_unauthorized
      TUNNEL_MSG="Playit rundata rejected the Agent key (HTTP 401)."
      playit_agent_failure invalid_secret "$TUNNEL_MSG" rundata_unauthorized
      return 1
      ;;
    403)
      TUNNEL_STATE=error
      TUNNEL_DIAGNOSTIC=rundata_forbidden
      TUNNEL_MSG="Playit rundata returned HTTP 403 (forbidden); this is not enough to identify the key as invalid."
      return 1
      ;;
    *)
      TUNNEL_STATE=error
      TUNNEL_DIAGNOSTIC=rundata_http_error
      TUNNEL_MSG="Playit rundata returned HTTP ${PLAYIT_API_HTTP_STATUS:-unknown}."
      log "PLAYIT_API_HTTP_ERROR status=${PLAYIT_API_HTTP_STATUS:-unknown}"
      return 1
      ;;
  esac
  [ -s "$PLAYIT_TEMP_DIR/rundata.json" ] || {
    TUNNEL_STATE=error
    TUNNEL_DIAGNOSTIC=rundata_empty
    TUNNEL_MSG="Playit returned HTTP ${PLAYIT_API_HTTP_STATUS:-2xx} with an empty rundata body."
    return 1
  }
  python3 nova-craft/playit.py parse "$PLAYIT_TEMP_DIR/rundata.json" "$PLAYIT_TEMP_DIR/tunnel.env" "$EDITION" "$PLAYIT_TUNNEL_ID" > /dev/null || {
    TUNNEL_STATE=error
    TUNNEL_DIAGNOSTIC=rundata_parse_error
    TUNNEL_MSG="The successful Playit rundata response could not be parsed as Tunnel data."
    return 1
  }
  . "$PLAYIT_TEMP_DIR/tunnel.env"
  TUNNEL_DIAGNOSTIC="${TUNNEL_DIAGNOSTIC:-$TUNNEL_STATE}"
  TUNNEL_MSG="${TUNNEL_Q_MSG:-}"
  return 0
}

record_playit_agent_exit() {
  [ -n "$PLAYIT_PID" ] || return 0
  [ "$PLAYIT_AGENT_EXIT_CAPTURED" = "true" ] && return 0
  local exit_code
  if wait "$PLAYIT_PID"; then exit_code=0; else exit_code=$?; fi
  PLAYIT_AGENT_EXIT_CODE="$exit_code"
  PLAYIT_AGENT_EXIT_CAPTURED=true
}

stop_failed_playit_agent() {
  [ -n "$PLAYIT_PID" ] || return 0
  if kill -0 "$PLAYIT_PID" 2>/dev/null; then
    kill -TERM "$PLAYIT_PID" 2>/dev/null || true
    for _ in $(seq 1 5); do
      kill -0 "$PLAYIT_PID" 2>/dev/null || break
      sleep 1
    done
    kill -KILL "$PLAYIT_PID" 2>/dev/null || true
  fi
  if [ "$PLAYIT_AGENT_EXIT_CAPTURED" != "true" ]; then
    wait "$PLAYIT_PID" 2>/dev/null || true
    PLAYIT_AGENT_EXIT_CAPTURED=true
  fi
  PLAYIT_AGENT_EXIT_CODE=stopped_after_failure
}

playit_agent_failure() {
  local diagnostic="$1" message="$2" tunnel_diagnostic="${3:-agent_$1}"
  case "$diagnostic" in
    process_exited|ipc_socket_failed) record_playit_agent_exit ;;
    *) stop_failed_playit_agent ;;
  esac
  PLAYIT_AGENT_STATUS=failed
  PLAYIT_AGENT_DIAGNOSTIC="$diagnostic"
  TUNNEL_STATE=error
  TUNNEL_DIAGNOSTIC="$tunnel_diagnostic"
  TUNNEL_MSG="$message"
  export PLAYIT_AGENT_STATUS PLAYIT_AGENT_DIAGNOSTIC PLAYIT_SECRET_STATUS SERVER_PORT_STATUS GAME_PORT
  export TUNNEL_STATE TUNNEL_MSG TUNNEL_DIAGNOSTIC TUNNEL_ADDR TUNNEL_NAME TUNNEL_ID TUNNEL_PROTO TUNNEL_ISSUE TUNNEL_LOCAL_IP TUNNEL_LOCAL_PORT AGENT_ID
  log "PLAYIT_AGENT_FAILED diagnostic=$PLAYIT_AGENT_DIAGNOSTIC exit_code=$PLAYIT_AGENT_EXIT_CODE"
  publish_status starting false "playit-agent-failed" "" "" "$TUNNEL_STATE" "$TUNNEL_MSG"
}

start_playit() {
  TUNNEL_STATE=unknown
  TUNNEL_DIAGNOSTIC=secret_missing
  TUNNEL_MSG="Playit Agent has not started; save PLAYIT_SECRET_KEY and start the server cycle."
  TUNNEL_ADDR=""
  TUNNEL_NAME=""
  TUNNEL_ID=""
  TUNNEL_PROTO=""
  TUNNEL_ISSUE=""
  TUNNEL_LOCAL_IP=""
  TUNNEL_LOCAL_PORT=""
  AGENT_ID=""
  PLAYIT_AGENT_EXIT_CODE=not_started
  PLAYIT_AGENT_EXIT_CAPTURED=false
  PLAYIT_AGENT_STATUS=not_started
  PLAYIT_AGENT_DIAGNOSTIC=secret_missing
  if [ -z "${PLAYIT_SECRET_KEY:-}" ]; then
    PLAYIT_SECRET_STATUS=missing
    export PLAYIT_AGENT_STATUS PLAYIT_AGENT_DIAGNOSTIC PLAYIT_AGENT_EXIT_CODE PLAYIT_SECRET_STATUS SERVER_PORT_STATUS GAME_PORT
    export TUNNEL_STATE TUNNEL_MSG TUNNEL_DIAGNOSTIC TUNNEL_ADDR TUNNEL_NAME TUNNEL_ID TUNNEL_PROTO TUNNEL_ISSUE TUNNEL_LOCAL_IP TUNNEL_LOCAL_PORT AGENT_ID
    log "PLAYIT_SECRET_INJECTED=false; Agent was not started"
    return 0
  fi

  # Move the injected key into an unexported local and immediately remove the
  # workflow environment variable; it was already registered for log masking.
  local secret_value="$PLAYIT_SECRET_KEY"
  unset PLAYIT_SECRET_KEY
  PLAYIT_SECRET_STATUS=saved
  if [[ ! "$secret_value" =~ ^([[:xdigit:]]{2})+$ ]]; then
    unset secret_value
    playit_agent_failure invalid_secret_format "The supplied Playit Agent key has an invalid format. Save the official Agent SECRET_KEY again."
    return 0
  fi

  local run_tag="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
  local runner_temp="${RUNNER_TEMP:-/tmp}"
  mkdir -p -- "$runner_temp" || {
    unset secret_value
    playit_agent_failure temp_directory_unavailable "The private runner temporary directory could not be created."
    return 0
  }
  PLAYIT_TEMP_DIR="$(mktemp -d "$runner_temp/nova-playit-${run_tag}.XXXXXX")" || {
    unset secret_value
    playit_agent_failure temp_directory_unavailable "The private runner temporary directory could not be created."
    return 0
  }
  if ! chmod 700 "$PLAYIT_TEMP_DIR"; then
    unset secret_value
    playit_agent_failure secure_temp_directory_failed "Could not secure the temporary directory for the Playit Agent key."
    return 0
  fi
  PLAYIT_SECRET_FILE="$PLAYIT_TEMP_DIR/agent.secret"
  PLAYIT_CURL_CONFIG="$PLAYIT_TEMP_DIR/api.curl"
  PLAYIT_LOG_PATH="$PLAYIT_TEMP_DIR/agent.log"
  local previous_umask secret_file_error=""
  previous_umask="$(umask)"
  umask 077
  if ! printf '%s' "$secret_value" > "$PLAYIT_SECRET_FILE"; then
    secret_file_error=write_secret_failed
  elif ! printf 'header = "Authorization: Agent-Key %s"\n' "$secret_value" > "$PLAYIT_CURL_CONFIG"; then
    secret_file_error=write_api_config_failed
  elif ! : > "$PLAYIT_LOG_PATH"; then
    secret_file_error=create_log_failed
  elif ! chmod 600 "$PLAYIT_SECRET_FILE" "$PLAYIT_CURL_CONFIG" "$PLAYIT_LOG_PATH"; then
    secret_file_error=secure_temp_files_failed
  fi
  umask "$previous_umask"
  unset secret_value
  if [ -n "$secret_file_error" ]; then
    playit_agent_failure "$secret_file_error" "Could not create or secure the temporary Playit Agent files."
    return 0
  fi
  export PLAYIT_SECRET_FILE PLAYIT_LOG_PATH
  PLAYIT_AGENT_STATUS=starting
  PLAYIT_AGENT_DIAGNOSTIC=starting
  PLAYIT_AGENT_EXIT_CODE=not_started
  TUNNEL_STATE=unknown
  TUNNEL_DIAGNOSTIC=agent_starting
  TUNNEL_MSG="Official Playit Agent is starting; connection is not confirmed yet."
  export PLAYIT_AGENT_STATUS PLAYIT_AGENT_DIAGNOSTIC PLAYIT_AGENT_EXIT_CODE PLAYIT_SECRET_STATUS SERVER_PORT_STATUS GAME_PORT
  export TUNNEL_STATE TUNNEL_MSG TUNNEL_DIAGNOSTIC TUNNEL_ADDR TUNNEL_NAME TUNNEL_ID TUNNEL_PROTO TUNNEL_ISSUE TUNNEL_LOCAL_IP TUNNEL_LOCAL_PORT AGENT_ID
  log "PLAYIT_SECRET_INJECTED=true (secret value redacted)"
  publish_status starting false "playit-agent-starting" "" "" "$TUNNEL_STATE" "$TUNNEL_MSG"

  local url="https://github.com/playit-cloud/playit-agent/releases/download/v1.0.10/playit-linux-amd64"
  local expected_sha="2df7d9f10227ab312b1ad341853db4e8a8243df5cfcdbae58713a4271711c339"
  if [ -x "$WORKSPACE_ABS/playitd" ] && ! printf '%s  %s\n' "$expected_sha" "$WORKSPACE_ABS/playitd" | sha256sum -c --status; then
    log "cached Playit daemon checksum mismatch; discarding binary"
    rm -f "$WORKSPACE_ABS/playitd"
  fi
  if [ ! -x "$WORKSPACE_ABS/playitd" ]; then
    if ! curl -fsSL --retry 3 --connect-timeout 20 -o "$WORKSPACE_ABS/playitd.tmp" "$url"; then
      rm -f "$WORKSPACE_ABS/playitd.tmp"
      playit_agent_failure agent_download_failed "The official Playit daemon download failed."
      return 0
    fi
    if [ ! -s "$WORKSPACE_ABS/playitd.tmp" ]; then
      rm -f "$WORKSPACE_ABS/playitd.tmp"
      playit_agent_failure agent_download_failed "The official Playit daemon download was empty."
      return 0
    fi
    if ! printf '%s  %s\n' "$expected_sha" "$WORKSPACE_ABS/playitd.tmp" | sha256sum -c --status; then
      rm -f "$WORKSPACE_ABS/playitd.tmp"
      playit_agent_failure agent_checksum_failed "The official Playit daemon checksum did not match; the binary was rejected."
      return 0
    fi
    chmod 700 "$WORKSPACE_ABS/playitd.tmp"
    mv "$WORKSPACE_ABS/playitd.tmp" "$WORKSPACE_ABS/playitd"
  fi

  # One official daemon process for this server cycle. It consumes the raw key
  # through a 0600 file; SECRET_KEY is never placed on argv or in its env.
  # GitHub-hosted runners may not have Playit's default IPC parent directory.
  # Keep its socket inside this run's already-created private temp directory.
  nohup "$WORKSPACE_ABS/playitd" --secret-path "$PLAYIT_SECRET_FILE" \
    --socket-path "$PLAYIT_TEMP_DIR/playit.sock" --platform-docker \
    > "$PLAYIT_LOG_PATH" 2>&1 </dev/null &
  PLAYIT_PID=$!
  PLAYIT_AGENT_EXIT_CODE=running
  PLAYIT_AGENT_EXIT_CAPTURED=false
  local attempt="" failure_diagnostic="startup_timeout"
  for attempt in $(seq 1 45); do
    if ! kill -0 "$PLAYIT_PID" 2>/dev/null; then
      record_playit_agent_exit
      if grep -Eiq 'IPC error: Failed to bind to socket|failed to bind.*socket' "$PLAYIT_LOG_PATH"; then
        failure_diagnostic=ipc_socket_failed
      else
        failure_diagnostic=process_exited
      fi
      break
    fi
    if grep -Fiq 'playit connected; tunnels loaded' "$PLAYIT_LOG_PATH"; then
      PLAYIT_AGENT_STATUS=connected
      PLAYIT_AGENT_DIAGNOSTIC=connected
      break
    fi
    if grep -Eiq 'InvalidAgentKey|invalid agent key|invalid secret|unauthori[sz]ed|no longer valid' "$PLAYIT_LOG_PATH"; then
      failure_diagnostic=invalid_secret
      break
    fi
    if grep -Eiq 'AgentDisabledOverLimit|agent limit|over the agent limit' "$PLAYIT_LOG_PATH"; then
      failure_diagnostic=account_agent_limit
      break
    fi
    if grep -Eiq 'Could not connect|Could not reach|failed to connect|timed out while connecting|connection refused|network is unreachable|temporary failure in name resolution|Name or service not known' "$PLAYIT_LOG_PATH"; then
      failure_diagnostic=network_unreachable
      break
    fi
    if [ $((attempt % 5)) -eq 0 ]; then
      export PLAYIT_AGENT_STATUS PLAYIT_AGENT_DIAGNOSTIC PLAYIT_SECRET_STATUS SERVER_PORT_STATUS GAME_PORT
      publish_status starting false "playit-agent-starting" "" "" "$TUNNEL_STATE" "$TUNNEL_MSG"
    fi
    sleep 2
  done
  if [ "$PLAYIT_AGENT_STATUS" != "connected" ]; then
    case "$failure_diagnostic" in
      invalid_secret)
        playit_agent_failure invalid_secret "Playit rejected the Agent SECRET_KEY. Save the official key again."
        ;;
      account_agent_limit)
        playit_agent_failure account_agent_limit "The Playit account has reached its Agent limit."
        ;;
      process_exited)
        playit_agent_failure process_exited "The official Playit Agent exited before connecting (exit code ${PLAYIT_AGENT_EXIT_CODE})."
        ;;
      ipc_socket_failed)
        playit_agent_failure ipc_socket_failed "The Playit Agent could not bind its local IPC socket; check the runner's temporary socket path."
        ;;
      *)
        PLAYIT_AGENT_STATUS=starting
        PLAYIT_AGENT_DIAGNOSTIC="$failure_diagnostic"
        TUNNEL_STATE=unknown
        TUNNEL_DIAGNOSTIC="agent_$failure_diagnostic"
        TUNNEL_MSG="Playit has not confirmed Agent connectivity; the daemon is still running and will retry."
        export PLAYIT_AGENT_STATUS PLAYIT_AGENT_DIAGNOSTIC PLAYIT_AGENT_EXIT_CODE PLAYIT_SECRET_STATUS SERVER_PORT_STATUS GAME_PORT
        export TUNNEL_STATE TUNNEL_MSG TUNNEL_DIAGNOSTIC TUNNEL_ADDR TUNNEL_NAME TUNNEL_ID TUNNEL_PROTO TUNNEL_ISSUE TUNNEL_LOCAL_IP TUNNEL_LOCAL_PORT AGENT_ID
        log "PLAYIT_AGENT_STILL_STARTING diagnostic=$PLAYIT_AGENT_DIAGNOSTIC exit_code=$PLAYIT_AGENT_EXIT_CODE"
        publish_status starting false "playit-agent-starting" "" "" "$TUNNEL_STATE" "$TUNNEL_MSG"
        ;;
    esac
    return 0
  fi

  PLAYIT_AGENT_STATUS=connected
  PLAYIT_AGENT_DIAGNOSTIC=connected
  PLAYIT_AGENT_EXIT_CODE=running
  TUNNEL_DIAGNOSTIC=agent_connected
  TUNNEL_MSG="Official Playit Agent confirmed connected; tunnels loaded."
  export PLAYIT_AGENT_STATUS PLAYIT_AGENT_DIAGNOSTIC PLAYIT_AGENT_EXIT_CODE PLAYIT_SECRET_STATUS SERVER_PORT_STATUS GAME_PORT
  log "PLAYIT_AGENT_CONNECTED: official daemon log confirmed 'playit connected; tunnels loaded'"
  if refresh_tunnel; then
    case "$TUNNEL_STATE" in
      allocated) TUNNEL_MSG="Playit reports $TUNNEL_ADDR; the local game port and external game-protocol ping are still being checked." ;;
      disabled) TUNNEL_MSG="Playit reports this Tunnel as disabled (${TUNNEL_ISSUE:-no reason given})." ;;
      not_created) TUNNEL_MSG="No matching Playit Tunnel was reported. Create one manually in the Playit dashboard; NOVA CRAFT does not create it." ;;
      unsupported) TUNNEL_MSG="The reported Tunnel type or transport is unsupported for this Minecraft edition." ;;
      address_unavailable) TUNNEL_MSG="The matching Playit Tunnel exists, but its public address is unavailable." ;;
      selection_required) TUNNEL_MSG="Several matching Playit Tunnels exist or the saved selection is unavailable; select one in NOVA CRAFT." ;;
      error) [ -n "$TUNNEL_MSG" ] || TUNNEL_MSG="The official Agent is connected, but Playit did not return usable Tunnel data." ;;
    esac
  else
    [ "$PLAYIT_AGENT_STATUS" = "failed" ] || TUNNEL_STATE=error
    [ -n "$TUNNEL_MSG" ] || TUNNEL_MSG="The Playit rundata request failed after Agent startup."
  fi
  export PLAYIT_AGENT_STATUS PLAYIT_AGENT_DIAGNOSTIC PLAYIT_SECRET_STATUS SERVER_PORT_STATUS GAME_PORT
  export TUNNEL_STATE TUNNEL_MSG TUNNEL_ADDR TUNNEL_NAME TUNNEL_ID TUNNEL_PROTO TUNNEL_ISSUE TUNNEL_LOCAL_IP TUNNEL_LOCAL_PORT AGENT_ID
  publish_status starting false "playit-agent-checked" "" "" "$TUNNEL_STATE" "$TUNNEL_MSG"
}

TUNNEL_STATE=unknown
TUNNEL_DIAGNOSTIC=minecraft_starting
TUNNEL_MSG="Minecraft is starting. The Playit Agent will start only after the local game protocol responds."
TUNNEL_ADDR=""
TUNNEL_NAME=""
TUNNEL_ID=""
TUNNEL_PROTO=""
TUNNEL_LOCAL_IP=""
TUNNEL_LOCAL_PORT=""
TUNNEL_ISSUE=""
AGENT_ID=""
PLAYIT_PID=""
PLAYIT_CURL_CONFIG=""
export TUNNEL_STATE TUNNEL_MSG TUNNEL_DIAGNOSTIC TUNNEL_ADDR TUNNEL_NAME TUNNEL_ID TUNNEL_PROTO TUNNEL_ISSUE TUNNEL_LOCAL_IP TUNNEL_LOCAL_PORT AGENT_ID
export PLAYIT_AGENT_STATUS PLAYIT_AGENT_DIAGNOSTIC PLAYIT_AGENT_EXIT_CODE PLAYIT_SECRET_STATUS SERVER_PORT_STATUS GAME_PORT
publish_status starting false "minecraft-starting" "" "" "$TUNNEL_STATE" "$TUNNEL_MSG"

# ---------------------------------------------------------------- runtime ---

cd "$DATA_ABS" || exit 1
FIFO=/tmp/nova-stdin
rm -f "$FIFO"; mkfifo "$FIFO"
exec 7<>"$FIFO"

if [ "$EDITION" = "JAVA" ]; then
  java -Xms512M -Xmx${MEMORY}M -XX:+UseG1GC -jar server.jar nogui < "$FIFO" > server.log 2>&1 &
else
  LD_LIBRARY_PATH=. ./bedrock_server < "$FIFO" > server.log 2>&1 &
fi
SRV_PID=$!
cd "$WORKSPACE_ABS" || exit 1
log "server pid $SRV_PID"

send_cmd() { printf '%s\n' "$1" >&7 2>/dev/null || true; }

wait_for_save() {
  local start_offset="$1" log_file="$DATA_ABS/server.log" pattern
  if [ "$EDITION" = "BEDROCK" ]; then
    pattern='Data saved\. Files are now ready to be copied'
  else
    pattern='Saved the game|All chunks are saved'
  fi
  for _ in $(seq 1 150); do
    if [ -f "$log_file" ] && tail -c +$((start_offset + 1)) "$log_file" 2>/dev/null | grep -qiE "$pattern"; then
      return 0
    fi
    kill -0 "$SRV_PID" 2>/dev/null || return 1
    sleep 2
  done
  return 1
}

SERVER_READY=false
READY_DEADLINE=$(( $(date +%s) + 900 ))
while kill -0 "$SRV_PID" 2>/dev/null; do
  if grep -qE "Done \([0-9.]+s\)!|Server started\." "$DATA_ABS/server.log" 2>/dev/null; then SERVER_READY=true; break; fi
  if [ "$(date +%s)" -gt "$READY_DEADLINE" ]; then break; fi
  sleep 3
done

# The first status is published only after the process check below, so a
# crashed server is never reported as ready.
if ! kill -0 "$SRV_PID" 2>/dev/null && [ "$SERVER_READY" != "true" ]; then
  log "ERROR the server exited before it became ready"
  tail -n 80 "$DATA_ABS/server.log" || true
  if [ -n "$PLAYIT_PID" ]; then
    if kill -0 "$PLAYIT_PID" 2>/dev/null; then
      [ "$PLAYIT_AGENT_STATUS" = "failed" ] || { PLAYIT_AGENT_STATUS=stopped; PLAYIT_AGENT_DIAGNOSTIC=cycle_ended; }
      kill "$PLAYIT_PID" 2>/dev/null || true
    elif [ "$PLAYIT_AGENT_STATUS" != "failed" ]; then
      PLAYIT_AGENT_STATUS=failed
      PLAYIT_AGENT_DIAGNOSTIC=process_exited
    fi
  fi
  if [ "$PLAYIT_AGENT_STATUS" = "stopped" ]; then
    TUNNEL_STATE=unknown
    TUNNEL_ADDR=""
    TUNNEL_MSG="The Minecraft process failed before the cycle was ready; the Playit Agent has stopped."
  fi
  export PLAYIT_AGENT_STATUS PLAYIT_AGENT_DIAGNOSTIC PLAYIT_SECRET_STATUS SERVER_PORT_STATUS GAME_PORT
  export TUNNEL_STATE TUNNEL_MSG TUNNEL_ADDR TUNNEL_NAME TUNNEL_ID TUNNEL_PROTO TUNNEL_ISSUE TUNNEL_LOCAL_IP TUNNEL_LOCAL_PORT AGENT_ID
  publish_live "$DATA_ABS/server.log"
  publish_cycle_end failure "server-crashed"
  exit 1
fi
if [ "$SERVER_READY" != "true" ]; then
  log "ERROR Minecraft did not report ready within 900 seconds; Playit Agent was not started"
  tail -n 80 "$DATA_ABS/server.log" || true
  send_cmd "stop"
  kill "$SRV_PID" 2>/dev/null || true
  SERVER_PORT_STATUS=not_listening
  TUNNEL_STATE=server_port_not_listening
  TUNNEL_DIAGNOSTIC=minecraft_start_timeout
  TUNNEL_MSG="Minecraft did not become ready within 900 seconds; Playit Agent was not started."
  export SERVER_PORT_STATUS GAME_PORT TUNNEL_STATE TUNNEL_MSG TUNNEL_DIAGNOSTIC
  publish_live "$DATA_ABS/server.log"
  publish_cycle_end failure "server-start-timeout"
  exit 1
fi

players_count() {
  local line
  # Java: "There are 0 of a max of 20 players online"
  # Bedrock: "There are 0/10 players online"
  line="$(grep -oE "There are [0-9]+ of a max of [0-9]+ players online" "$DATA_ABS/server.log" 2>/dev/null | tail -1)"
  if [ -z "$line" ]; then
    line="$(grep -oE "There are [0-9]+/[0-9]+ players online" "$DATA_ABS/server.log" 2>/dev/null | tail -1 | sed -E 's|There are ([0-9]+)/([0-9]+) players online|There are \1 of a max of \2 players online|')"
  fi
  if [ -n "$line" ]; then echo "$line"; fi
}
parse_players() { echo "$1" | grep -oE "[0-9]+" | head -1; }
parse_max() { echo "$1" | grep -oE "[0-9]+" | sed -n 2p; }

# Confirm the local Minecraft endpoint with an actual game-protocol ping; a
# startup log line alone is not evidence that port 25565/19132 is reachable.
if [ "$EDITION" = "JAVA" ] && ! wait_for_port 127.0.0.1 "$GAME_PORT" 60; then
  log "WARN local Java TCP port $GAME_PORT did not accept a socket within 60 seconds"
fi
if probe_tunnel "127.0.0.1:$GAME_PORT" false; then
  SERVER_PORT_STATUS=listening
else
  SERVER_PORT_STATUS=not_listening
fi
if [ "$SERVER_PORT_STATUS" = "listening" ]; then
  # Start the official daemon only after Minecraft answered its local game
  # protocol. This keeps an Agent failure independent from server readiness.
  start_playit
  LAST_TUNNEL_REFRESH=$(date +%s)
else
  PLAYIT_AGENT_STATUS=not_started
  PLAYIT_AGENT_DIAGNOSTIC=minecraft_port_not_listening
  PLAYIT_AGENT_EXIT_CODE=not_started
  TUNNEL_STATE=server_port_not_listening
  TUNNEL_DIAGNOSTIC=server_port_not_listening
  TUNNEL_ADDR=""
  TUNNEL_MSG="Minecraft did not answer its local game protocol on port $GAME_PORT; Playit Agent was not started."
  log "PLAYIT_AGENT_NOT_STARTED reason=minecraft_port_not_listening game_port=$GAME_PORT"
fi
export SERVER_PORT_STATUS GAME_PORT PLAYIT_AGENT_STATUS PLAYIT_AGENT_DIAGNOSTIC PLAYIT_AGENT_EXIT_CODE PLAYIT_SECRET_STATUS
export TUNNEL_STATE TUNNEL_MSG TUNNEL_DIAGNOSTIC TUNNEL_ADDR TUNNEL_NAME TUNNEL_ID TUNNEL_PROTO TUNNEL_ISSUE TUNNEL_LOCAL_IP TUNNEL_LOCAL_PORT AGENT_ID

# Start the five-hour runtime budget only after local Minecraft readiness and
# the Agent/Tunnel checks have completed (or their failure has been diagnosed).
JOB_STARTED=$(date +%s)
publish_live "$DATA_ABS/server.log"
publish_files
publish_status ready true "server-ready" "$(parse_players "$(players_count)")" "$(parse_max "$(players_count)")" "$TUNNEL_STATE" "$TUNNEL_MSG"

STOP_FLAG=/tmp/nova-stop
BACKUP_REQUEST_FLAG=/tmp/nova-backup-request
rm -f "$STOP_FLAG" "$BACKUP_REQUEST_FLAG"
BACKUP_DONE=false
LAST_FILE_REQ=""
LAST_FILES_PUBLISH=$(date +%s)

poll_commands() {
  while kill -0 "$SRV_PID" 2>/dev/null; do
    sleep 12
    apply_file_request
    local files
    files="$(gh api "repos/$REPO/contents/nova-craft/commands" --jq '[.[] | select(.type=="file" and (.name | endswith(".txt")))] | sort_by(.name) | .[].name' 2>/dev/null || true)"
    for f in $files; do
      local cmd sha
      cmd="$(gh api "repos/$REPO/contents/nova-craft/commands/$f" --jq .content 2>/dev/null | base64 -d 2>/dev/null | tr -d '\r\n')"
      sha="$(gh api "repos/$REPO/contents/nova-craft/commands/$f" --jq .sha 2>/dev/null)"
      case "$cmd" in
        "nova:stop") touch "$STOP_FLAG"; send_cmd "say NOVA CRAFT is stopping";;
        "nova:backup") touch "$BACKUP_REQUEST_FLAG"; log "backup requested from the app";;
        "") : ;;
        *)
          if [ "$ALLOW_COMMANDS" = "true" ]; then
            log "manual command accepted"
            send_cmd "$cmd"
          else
            log "manual command rejected: console commands are disabled"
          fi
          ;;
      esac
      [ -n "$sha" ] && gh api -X DELETE "repos/$REPO/contents/nova-craft/commands/$f" \
        -f message="nova: command consumed" -f sha="$sha" > /dev/null 2>&1 || true
      sleep 1
    done
  done
}

heartbeat() {
  while kill -0 "$SRV_PID" 2>/dev/null; do
    sleep 30
    local players line latency now
    line="$(players_count)"
    players="$(parse_players "$line")"

    # The local game endpoint is checked independently of the Agent and Tunnel.
    if probe_tunnel "127.0.0.1:$GAME_PORT" false; then
      SERVER_PORT_STATUS=listening
    else
      SERVER_PORT_STATUS=not_listening
    fi

    if [ -n "$PLAYIT_PID" ]; then
      if ! kill -0 "$PLAYIT_PID" 2>/dev/null; then
        if [ "$PLAYIT_AGENT_STATUS" != "failed" ]; then
          record_playit_agent_exit
          PLAYIT_AGENT_STATUS=failed
          PLAYIT_AGENT_DIAGNOSTIC=process_exited
          TUNNEL_STATE=error
          TUNNEL_DIAGNOSTIC=agent_process_exited
          TUNNEL_MSG="The Playit Agent exited while Minecraft was running (exit code ${PLAYIT_AGENT_EXIT_CODE})."
          log "PLAYIT_AGENT_FAILED diagnostic=process_exited exit_code=$PLAYIT_AGENT_EXIT_CODE"
        fi
      elif grep -Fiq 'playit connected; tunnels loaded' "$PLAYIT_LOG_PATH"; then
        if [ "$PLAYIT_AGENT_STATUS" != "connected" ]; then
          PLAYIT_AGENT_STATUS=connected
          PLAYIT_AGENT_DIAGNOSTIC=connected
          log "PLAYIT_AGENT_CONNECTED: official daemon log confirmed connection after startup retry"
          LAST_TUNNEL_REFRESH=0
        fi
      fi
    fi

    # Read late-created Tunnels once per minute, and only after the official
    # daemon confirms that it is connected. The runner never creates Tunnels.
    now=$(date +%s)
    if [ "$PLAYIT_AGENT_STATUS" = "connected" ] && [ $((now - LAST_TUNNEL_REFRESH)) -ge 60 ]; then
      LAST_TUNNEL_REFRESH=$now
      if refresh_tunnel; then
        case "$TUNNEL_STATE" in
          allocated) TUNNEL_MSG="Playit reports $TUNNEL_ADDR; waiting for local and external Minecraft protocol checks." ;;
          disabled) TUNNEL_MSG="Playit reports this Tunnel as disabled (${TUNNEL_ISSUE:-no reason given})." ;;
          not_created) TUNNEL_MSG="No matching Playit Tunnel was reported. Create one manually in the Playit dashboard." ;;
          unsupported) TUNNEL_MSG="The reported Tunnel type or transport is unsupported for this Minecraft edition." ;;
          address_unavailable) TUNNEL_MSG="The matching Playit Tunnel exists, but its public address is unavailable." ;;
          selection_required) TUNNEL_MSG="Select one matching Playit Tunnel in NOVA CRAFT." ;;
          error) [ -n "$TUNNEL_MSG" ] || TUNNEL_MSG="The official Agent is connected, but Playit did not return usable Tunnel data." ;;
        esac
      else
        TUNNEL_STATE=error
        [ -n "$TUNNEL_DIAGNOSTIC" ] || TUNNEL_DIAGNOSTIC=rundata_network_error
        [ -n "$TUNNEL_MSG" ] || TUNNEL_MSG="The Playit rundata refresh failed; inspect the sanitized API diagnostic."
      fi
    fi

    # Only an allocated, supported Tunnel can progress to Connection ready.
    # Java is probed using the Minecraft Server List Ping over TCP; Bedrock
    # uses RakNet's unconnected UDP ping. A raw socket connect is never enough.
    case "$TUNNEL_STATE" in
      allocated|connecting|connected|server_port_not_listening|origin_mismatch)
        if [ "$SERVER_PORT_STATUS" != "listening" ]; then
          TUNNEL_STATE=server_port_not_listening
          TUNNEL_DIAGNOSTIC=server_port_not_listening
          TUNNEL_MSG="The local Minecraft game port $GAME_PORT did not answer its protocol ping."
        elif [ "$PLAYIT_AGENT_STATUS" = "failed" ]; then
          TUNNEL_STATE=error
          TUNNEL_DIAGNOSTIC="agent_$PLAYIT_AGENT_DIAGNOSTIC"
          TUNNEL_MSG="The Playit Agent failed while Minecraft was running."
        elif [ "$PLAYIT_AGENT_STATUS" != "connected" ]; then
          TUNNEL_STATE=unknown
          TUNNEL_DIAGNOSTIC=agent_not_connected
          TUNNEL_MSG="Waiting for the official Playit Agent connection."
        elif [ -n "$TUNNEL_LOCAL_PORT" ] && [ "$TUNNEL_LOCAL_PORT" != "$GAME_PORT" ]; then
          TUNNEL_STATE=origin_mismatch
          TUNNEL_DIAGNOSTIC=origin_mismatch
          TUNNEL_MSG="The Playit Tunnel targets local port $TUNNEL_LOCAL_PORT; Minecraft is configured for port $GAME_PORT."
        elif [ -n "$TUNNEL_ADDR" ] && probe_tunnel "$TUNNEL_ADDR" true; then
          TUNNEL_STATE=connected
          TUNNEL_DIAGNOSTIC=connected
          if [ "$EDITION" = "BEDROCK" ]; then
            TUNNEL_MSG="Playit's reported address answered a Bedrock RakNet ping."
          else
            TUNNEL_MSG="Playit's reported address answered a Java Server List Ping."
          fi
        else
          TUNNEL_STATE=connecting
          TUNNEL_DIAGNOSTIC=connecting
          TUNNEL_MSG="The local game port is ready; waiting for Playit's public address to answer the Minecraft protocol ping."
        fi
        ;;
    esac

    export PLAYIT_AGENT_STATUS PLAYIT_AGENT_DIAGNOSTIC PLAYIT_AGENT_EXIT_CODE PLAYIT_SECRET_STATUS SERVER_PORT_STATUS GAME_PORT
    export TUNNEL_STATE TUNNEL_MSG TUNNEL_DIAGNOSTIC TUNNEL_ADDR TUNNEL_NAME TUNNEL_ID TUNNEL_PROTO TUNNEL_ISSUE TUNNEL_LOCAL_IP TUNNEL_LOCAL_PORT AGENT_ID
    latency=""
    publish_live "$DATA_ABS/server.log"
    if [ $(( $(date +%s) - LAST_FILES_PUBLISH )) -ge 300 ]; then
      LAST_FILES_PUBLISH=$(date +%s)
      publish_files
    fi
    publish_status ready true "server-ready" "$players" "$(parse_max "$line")" "$TUNNEL_STATE" "$TUNNEL_MSG" "$latency"
  done
}

poll_commands & POLL_PID=$!
heartbeat & HB_PID=$!

perform_manual_backup() {
  local save_log_offset
  rm -f "$BACKUP_REQUEST_FLAG"
  log "starting an on-demand, consistency-protected backup"
  save_log_offset="$(wc -c < "$DATA_ABS/server.log" 2>/dev/null || echo 0)"
  if [ "$EDITION" = "BEDROCK" ]; then
    send_cmd "save hold"
    send_cmd "save query"
  else
    send_cmd "save-off"
    send_cmd "save-all flush"
  fi
  if wait_for_save "$save_log_offset"; then
    if backup_now "manual"; then
      log "on-demand backup completed and verified"
    else
      log "ERROR on-demand backup did not complete"
    fi
  else
    log "ERROR save acknowledgement timed out; refusing to archive a possibly changing world"
  fi
  if [ "$EDITION" = "BEDROCK" ]; then
    send_cmd "save resume"
  else
    send_cmd "save-on"
  fi
}

while kill -0 "$SRV_PID" 2>/dev/null; do
  if [ -f "$STOP_FLAG" ]; then log "stop requested from the app"; break; fi
  if [ $(( $(date +%s) - JOB_STARTED )) -ge "$MAXSEC" ]; then log "cycle time limit reached"; break; fi
  if [ -f "$BACKUP_REQUEST_FLAG" ]; then perform_manual_backup; fi
  sleep 10
done

kill "$POLL_PID" "$HB_PID" 2>/dev/null || true
wait "$POLL_PID" "$HB_PID" 2>/dev/null || true

# Safe shutdown: flush and hold writes using edition-appropriate commands,
# verify the release backup, resume saves, then stop the server process.
publish_status stopping false "stopping"
SAVE_LOG_OFFSET="$(wc -c < "$DATA_ABS/server.log" 2>/dev/null || echo 0)"
if [ "$EDITION" = "BEDROCK" ]; then
  send_cmd "save hold"
  send_cmd "save query"
else
  send_cmd "save-off"
  send_cmd "save-all flush"
fi
if wait_for_save "$SAVE_LOG_OFFSET"; then
  if backup_now "cycle"; then BACKUP_DONE=true; fi
else
  log "ERROR save acknowledgement timed out; refusing to archive a possibly changing world"
fi
if [ "$EDITION" = "BEDROCK" ]; then
  send_cmd "save resume"
else
  send_cmd "save-on"
fi
send_cmd "stop"
for _ in $(seq 1 45); do kill -0 "$SRV_PID" 2>/dev/null || break; sleep 2; done
if kill -0 "$SRV_PID" 2>/dev/null; then log "server did not stop in time; killing"; kill -9 "$SRV_PID" 2>/dev/null || true; fi

exec 7>&- 2>/dev/null || true
if [ -n "$PLAYIT_PID" ]; then
  if kill -0 "$PLAYIT_PID" 2>/dev/null; then
    if [ "$PLAYIT_AGENT_STATUS" = "connected" ] || [ "$PLAYIT_AGENT_STATUS" = "starting" ]; then
      PLAYIT_AGENT_STATUS=stopped
      PLAYIT_AGENT_DIAGNOSTIC=cycle_ended
    fi
    kill "$PLAYIT_PID" 2>/dev/null || true
    wait "$PLAYIT_PID" 2>/dev/null || true
    PLAYIT_AGENT_EXIT_CODE=cycle_ended
    PLAYIT_AGENT_EXIT_CAPTURED=true
  elif [ "$PLAYIT_AGENT_STATUS" != "failed" ] && [ "$PLAYIT_AGENT_STATUS" != "not_started" ]; then
    record_playit_agent_exit
    PLAYIT_AGENT_STATUS=failed
    PLAYIT_AGENT_DIAGNOSTIC=process_exited
    TUNNEL_STATE=error
    TUNNEL_DIAGNOSTIC=agent_process_exited
    TUNNEL_MSG="The Playit Agent exited before the cycle ended (exit code ${PLAYIT_AGENT_EXIT_CODE})."
  fi
fi
if [ "$PLAYIT_AGENT_STATUS" = "stopped" ]; then
  TUNNEL_STATE=unknown
  TUNNEL_DIAGNOSTIC=cycle_ended
  TUNNEL_ADDR=""
  TUNNEL_MSG="The GitHub Actions server cycle ended; the Agent and live Tunnel are no longer running."
fi
SERVER_PORT_STATUS=unknown
export PLAYIT_AGENT_STATUS PLAYIT_AGENT_DIAGNOSTIC PLAYIT_AGENT_EXIT_CODE PLAYIT_SECRET_STATUS SERVER_PORT_STATUS GAME_PORT
export TUNNEL_STATE TUNNEL_MSG TUNNEL_DIAGNOSTIC TUNNEL_ADDR TUNNEL_NAME TUNNEL_ID TUNNEL_PROTO TUNNEL_ISSUE TUNNEL_LOCAL_IP TUNNEL_LOCAL_PORT AGENT_ID

publish_live "$DATA_ABS/server.log"
publish_files
tail -n 120 "$DATA_ABS/server.log" || true

if [ "$BACKUP_DONE" != "true" ]; then
  log "WARN no backup could be uploaded this cycle"
  publish_cycle_end failure "backup-failed"
  exit 1
fi

publish_cycle_end success "cycle-finished"

if [ ! -f "$STOP_FLAG" ] && [ "$AUTORESTART" = "true" ]; then
  log "dispatching the next cycle"
  gh workflow run novacraft-server.yml --repo "$REPO" --ref "$REF" -f action=start || \
    log "WARN could not dispatch the next cycle (time limit reached?)"
fi
''';

  /// Playit agent-API helper executed on the runner (no secret is printed).
  static const String playitScript = r'''
#!/usr/bin/env python3
# Select only a user-designated tunnel or the single unambiguous matching one.
# This helper never creates tunnels and never prints the agent secret.
import json
import re
import shlex
import socket
import sys
import time

TYPES = {"JAVA": "minecraft-java", "BEDROCK": "minecraft-bedrock"}


def load(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def unwrap(raw):
    if not isinstance(raw, dict):
        return {}, "invalid-response"
    status = str(raw.get("status", "")).lower()
    if status in ("fail", "error"):
        return {}, "api-error"
    data = raw.get("data")
    if isinstance(data, dict):
        return data, ""
    success = raw.get("success")
    if isinstance(success, dict):
        return success, ""
    return raw, ""


def tunnel_id(tunnel):
    return str(tunnel.get("tunnel_id") or tunnel.get("id") or "")


def pick_tunnel(tunnels, edition, requested_id):
    wanted = TYPES.get(edition.upper(), TYPES["JAVA"])
    expected_port = "udp" if edition.upper() == "BEDROCK" else "tcp"
    compatible = [t for t in tunnels
                  if str(t.get("tunnel_type") or "") == wanted
                  and str(t.get("port_type") or "").lower() == expected_port]
    if requested_id:
        selected = next((t for t in tunnels if tunnel_id(t) == requested_id), None)
        if selected is None:
            return None, "The selected Playit Tunnel was not returned by the agent.", "selection_required"
        if str(selected.get("tunnel_type") or "") != wanted or str(selected.get("port_type") or "").lower() != expected_port:
            return None, "Tunnel type unsupported for this Minecraft edition and transport.", "unsupported"
        return selected, "", ""
    if len(compatible) == 1:
        return compatible[0], "", ""
    if len(compatible) > 1:
        return None, "Several matching Playit Tunnels exist; select one in NOVA CRAFT.", "selection_required"
    if tunnels:
        return None, "Tunnel type unsupported for this Minecraft edition and transport.", "unsupported"
    return None, "This Playit agent has no Tunnel yet. Create one manually in Playit.", "not_created"


def tunnel_field(tunnel, name):
    direct = tunnel.get(name)
    if direct is not None and str(direct):
        return str(direct)
    config = tunnel.get("agent_config")
    fields = config.get("fields") if isinstance(config, dict) else None
    if isinstance(fields, dict) and fields.get(name) is not None:
        return str(fields[name])
    if isinstance(fields, list):
        for field in fields:
            if isinstance(field, dict) and str(field.get("name") or "") == name:
                return str(field.get("value") or field.get("default_value") or "")
    return ""


def parse_host_port(address, edition):
    address = address.replace("tcp://", "").replace("udp://", "")
    host, sep, raw_port = address.rpartition(":")
    if not sep:
        host, raw_port = address, "19132" if edition.upper() == "BEDROCK" else "25565"
    if host.startswith("[") and host.endswith("]"):
        host = host[1:-1]
    try:
        port = int(raw_port)
        if not host or not 1 <= port <= 65535:
            raise ValueError("invalid host or port")
        return host, port
    except (TypeError, ValueError):
        return None, None


def encode_varint(value):
    out = bytearray()
    while True:
        part = value & 0x7f
        value >>= 7
        if value:
            out.append(part | 0x80)
        else:
            out.append(part)
            return bytes(out)


def recv_exact(sock, length):
    chunks = bytearray()
    while len(chunks) < length:
        block = sock.recv(length - len(chunks))
        if not block:
            raise OSError("connection closed")
        chunks.extend(block)
    return bytes(chunks)


def read_varint(sock):
    value = 0
    for shift in range(0, 35, 7):
        byte = recv_exact(sock, 1)[0]
        value |= (byte & 0x7f) << shift
        if not byte & 0x80:
            return value
    raise ValueError("invalid VarInt")


def java_status_ping(host, port):
    # Java Server List Ping over TCP; a successful connect without its status
    # response is not accepted as a ready Minecraft endpoint.
    encoded_host = host.encode("utf-8")
    handshake = b"\x00" + encode_varint(767) + encode_varint(len(encoded_host)) + encoded_host + port.to_bytes(2, "big") + b"\x01"
    packet = encode_varint(len(handshake)) + handshake + b"\x01\x00"
    with socket.create_connection((host, port), timeout=6) as sock:
        sock.settimeout(6)
        sock.sendall(packet)
        packet_len = read_varint(sock)
        if packet_len <= 0 or packet_len > 65536:
            return False
        packet_id = read_varint(sock)
        json_len = read_varint(sock)
        if packet_id != 0 or json_len <= 0 or json_len > packet_len:
            return False
        payload = json.loads(recv_exact(sock, json_len).decode("utf-8", "replace"))
        return isinstance(payload, dict) and ("version" in payload or "players" in payload)


def bedrock_status_ping(host, port):
    # RakNet unconnected ping over UDP, including the documented offline magic.
    magic = bytes((0x00, 0xff, 0xff, 0x00, 0xfe, 0xfe, 0xfe, 0xfe, 0xfd, 0xfd, 0xfd, 0xfd, 0x12, 0x34, 0x56, 0x78))
    stamp = int(time.time() * 1000).to_bytes(8, "big", signed=False)
    packet = b"\x01" + stamp + magic + (123456789).to_bytes(8, "big", signed=False)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(6)
        sock.sendto(packet, (host, port))
        reply, _ = sock.recvfrom(4096)
    if len(reply) < 35 or reply[0] != 0x1c or reply[17:33] != magic:
        return False
    text_len = int.from_bytes(reply[33:35], "big")
    if text_len <= 0 or 35 + text_len > len(reply):
        return False
    fields = reply[35:35 + text_len].decode("utf-8", "replace").split(";")
    return len(fields) >= 2 and bool(fields[0])


def probe(address, edition):
    host, port = parse_host_port(address, edition)
    if not host:
        return False
    try:
        if edition.upper() == "BEDROCK":
            return bedrock_status_ping(host, port)
        return java_status_ping(host, port)
    except (OSError, ValueError, json.JSONDecodeError):
        return False


def parse(argv):
    raw = load(argv[0])
    out_path = argv[1]
    edition = argv[2] if len(argv) > 2 else "JAVA"
    requested_id = argv[3] if len(argv) > 3 else ""
    if raw is None:
        data, error = {}, "invalid-json"
    else:
        data, error = unwrap(raw)
    raw_tunnels = data.get("tunnels") if not error else None
    if not error and (not isinstance(data.get("agent_id"), str) or not data.get("agent_id") or not isinstance(raw_tunnels, list)):
        error = "invalid-schema"
    if not error:
        for tunnel in raw_tunnels:
            if (not isinstance(tunnel, dict)
                    or not isinstance(tunnel.get("id") or tunnel.get("tunnel_id"), str)
                    or not (tunnel.get("id") or tunnel.get("tunnel_id"))
                    or not isinstance(tunnel.get("name"), str)
                    or not isinstance(tunnel.get("port_type"), str)
                    or not isinstance(tunnel.get("display_address"), str)):
                error = "invalid-schema"
                break
    tunnels = raw_tunnels if not error else []
    chosen, message, selection_state = pick_tunnel(tunnels, edition, requested_id) if not error else (None, "", "error")
    diagnostic = {
        "invalid-json": "rundata_invalid_json",
        "invalid-schema": "rundata_invalid_schema",
        "invalid-response": "rundata_invalid_response",
        "api-error": "rundata_api_error",
    }.get(error, "")
    error_message = {
        "invalid-json": "Playit rundata response was not valid JSON.",
        "invalid-schema": "Playit rundata did not contain a valid agent ID and Tunnel list.",
        "invalid-response": "Playit rundata response had an unexpected JSON shape.",
        "api-error": "Playit agent API returned an error response.",
    }.get(error, "Playit rundata could not be interpreted.")
    values = {
        "AGENT_ID": str(data.get("agent_id") or ""),
        "TUNNEL_STATE": "error",
        "TUNNEL_DIAGNOSTIC": diagnostic,
        "TUNNEL_Q_MSG": "",
        "TUNNEL_ADDR": "",
        "TUNNEL_NAME": "",
        "TUNNEL_ID": "",
        "TUNNEL_PROTO": "",
        "TUNNEL_LOCAL_IP": "",
        "TUNNEL_LOCAL_PORT": "",
        "TUNNEL_ISSUE": "",
    }
    if error:
        values["TUNNEL_Q_MSG"] = error_message
    elif chosen:
        reason = chosen.get("disabled_reason")
        if isinstance(reason, dict):
            reason = reason.get("type") or "disabled"
        values["TUNNEL_STATE"] = "disabled" if reason else "allocated"
        values["TUNNEL_ADDR"] = str(chosen.get("display_address") or "")
        values["TUNNEL_NAME"] = str(chosen.get("name") or "")
        values["TUNNEL_ID"] = tunnel_id(chosen)
        values["TUNNEL_PROTO"] = str(chosen.get("port_type") or "")
        values["TUNNEL_LOCAL_IP"] = tunnel_field(chosen, "local_ip")
        local_port = tunnel_field(chosen, "local_port")
        if re.fullmatch(r"[0-9]{1,5}", local_port) and 1 <= int(local_port) <= 65535:
            values["TUNNEL_LOCAL_PORT"] = local_port
        values["TUNNEL_ISSUE"] = str(reason or "")
        if not values["TUNNEL_ADDR"]:
            values["TUNNEL_STATE"] = "address_unavailable"
            values["TUNNEL_Q_MSG"] = "Playit has not allocated a public address for this Tunnel yet."
    else:
        values["TUNNEL_STATE"] = selection_state
        values["TUNNEL_Q_MSG"] = message
    if not values["TUNNEL_DIAGNOSTIC"]:
        values["TUNNEL_DIAGNOSTIC"] = values["TUNNEL_STATE"]
    with open(out_path, "w", encoding="utf-8") as handle:
        for key, value in values.items():
            handle.write("%s=%s\n" % (key, shlex.quote(value)))
    print("tunnel state: %s" % values["TUNNEL_STATE"])
    return 0


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "parse" and len(sys.argv) >= 4:
        sys.exit(parse(sys.argv[2:]))
    if len(sys.argv) == 4 and sys.argv[1] == "probe":
        sys.exit(0 if probe(sys.argv[2], sys.argv[3]) else 1)
    print("usage: playit.py parse <rundata.json> <out.env> [edition] [tunnel_id] | probe <address> <edition>", file=sys.stderr)
    sys.exit(2)
''';

  /// Executed on the runner; see the docstring for the path guarantees.
  static const String fileOpsScript = r'''
#!/usr/bin/env python3
"""NOVA CRAFT server file operations.

Runs on the GitHub runner, inside/below the server data folder ONLY.
Every path is resolved and checked against the data root; anything that
escapes it is rejected (no traversal, no symlink escape).

Modes
  manifest <root> <out.json>
  request  <root> <request.json> <response.json>
  addons   <data_root> <addons_dir> <state.json> <out.json>
  import   <data_root> <zip> <world_name> <out.json>
"""
import base64
import json
import os
import re
import shutil
import sys
import tempfile
import time
import zipfile

MAX_READ = 700 * 1024
MAX_MANIFEST_ENTRIES = 4000
SKIP_DIRS = {"libraries", "versions", ".fabric", "cache", ".cache", "tmp", "crash-reports"}


def safe_data_root(root):
    root_abs = os.path.abspath(root)
    if os.path.islink(root_abs) or not os.path.isdir(root_abs):
        raise ValueError("unsafe data root")
    root_real = os.path.realpath(root_abs)
    if not os.path.isdir(root_real):
        raise ValueError("unsafe data root")
    return root_real


def safe_path(root, rel):
    root_real = safe_data_root(root)
    if rel is None or rel == "":
        return root_real
    if not isinstance(rel, str) or rel != rel.strip():
        raise ValueError("path-outside-root")
    normalized = rel.replace("\\", "/")
    if normalized == ".":
        return root_real
    parts = normalized.split("/")
    if (normalized.startswith("/") or any(part in ("", ".", "..") for part in parts)
            or re.match(r"^[A-Za-z]:", parts[0])):
        raise ValueError("path-outside-root")
    candidate = os.path.realpath(os.path.join(root_real, *parts))
    if candidate != root_real and not candidate.startswith(root_real + os.sep):
        raise ValueError("path-outside-root")
    return candidate


def manifest(root):
    root_real = safe_data_root(root)
    files = []
    dirs = []
    truncated = False
    for dirpath, dirnames, filenames in os.walk(root_real, followlinks=False):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not os.path.islink(os.path.join(dirpath, d))]
        rel_dir = os.path.relpath(dirpath, root_real).replace(os.sep, "/")
        if rel_dir != ".":
            dirs.append(rel_dir)
        for name in filenames:
            full = os.path.join(dirpath, name)
            if os.path.islink(full):
                continue
            try:
                st = os.stat(full)
            except OSError:
                continue
            rel = os.path.relpath(full, root_real).replace(os.sep, "/")
            files.append({"path": rel, "size": st.st_size, "modified": int(st.st_mtime)})
            if len(files) >= MAX_MANIFEST_ENTRIES:
                truncated = True
                break
        if truncated:
            break
    files.sort(key=lambda f: f["path"])
    dirs.sort()
    return {
        "schema": 1,
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "files": files,
        "dirs": dirs,
        "truncated": truncated,
    }


def _ok(**kwargs):
    out = {"ok": True}
    out.update(kwargs)
    return out


def _fail(code):
    return {"ok": False, "error": code}


def atomic_write_bytes(path, data):
    parent = os.path.dirname(os.path.abspath(path))
    os.makedirs(parent, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".nova-craft-", dir=parent)
    try:
        with os.fdopen(fd, "wb") as handle_file:
            handle_file.write(data)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def atomic_write_json(path, payload):
    data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    atomic_write_bytes(path, data)


def handle(root, request):
    op = (request.get("op") or "").lower()
    if op == "list":
        target = safe_path(root, request.get("path") or ".")
        if not os.path.isdir(target):
            return _fail("not-a-directory")
        rel_base = os.path.relpath(target, os.path.realpath(root)).replace(os.sep, "/")
        if rel_base == ".":
            rel_base = ""
        entries = []
        for name in sorted(os.listdir(target)):
            full = os.path.join(target, name)
            if os.path.islink(full):
                continue
            st = os.stat(full)
            entries.append({
                "name": name,
                "path": (rel_base + "/" + name).lstrip("/"),
                "dir": os.path.isdir(full),
                "size": 0 if os.path.isdir(full) else st.st_size,
                "modified": int(st.st_mtime),
            })
        return _ok(path=rel_base, files=entries)
    if op == "read":
        target = safe_path(root, request.get("path") or "")
        if not os.path.isfile(target):
            return _fail("not-a-file")
        size = os.path.getsize(target)
        with open(target, "rb") as handle_file:
            data = handle_file.read(MAX_READ)
        return _ok(
            path=os.path.relpath(target, os.path.realpath(root)).replace(os.sep, "/"),
            size=size,
            truncated=size > len(data),
            content=base64.b64encode(data).decode(),
        )
    if op == "write":
        target = safe_path(root, request.get("path") or "")
        if not request.get("path"):
            return _fail("missing-path")
        data = base64.b64decode(request.get("content") or "")
        if len(data) > 2 * 1024 * 1024:
            return _fail("too-large")
        os.makedirs(os.path.dirname(target) or os.path.realpath(root), exist_ok=True)
        # A fixed sibling temporary name could be pre-created as a symlink to
        # a file outside the server data root. mkstemp uses O_EXCL and a random
        # name, then replace atomically installs the new file.
        atomic_write_bytes(target, data)
        return _ok(path=os.path.relpath(target, os.path.realpath(root)).replace(os.sep, "/"), size=len(data))
    if op == "mkdir":
        target = safe_path(root, request.get("path") or "")
        if not request.get("path"):
            return _fail("missing-path")
        os.makedirs(target, exist_ok=True)
        return _ok(path=request.get("path"))
    if op == "rename":
        src = safe_path(root, request.get("path") or "")
        dest = safe_path(root, request.get("dest") or "")
        if not request.get("path") or not request.get("dest"):
            return _fail("missing-path")
        if not os.path.exists(src):
            return _fail("not-found")
        if os.path.exists(dest):
            return _fail("destination-exists")
        os.makedirs(os.path.dirname(dest) or root, exist_ok=True)
        os.replace(src, dest)
        return _ok(path=request.get("dest"))
    if op == "delete":
        target = safe_path(root, request.get("path") or "")
        if not request.get("path"):
            return _fail("missing-path")
        if os.path.isdir(target):
            shutil.rmtree(target)
        elif os.path.exists(target):
            os.remove(target)
        else:
            return _fail("not-found")
        return _ok(path=request.get("path"))
    return _fail("unknown-op")


def _zip_safe(zf, base):
    for member in zf.namelist():
        normalized = os.path.normpath(member).replace("\\", "/")
        if normalized.startswith("..") or normalized.startswith("/") or ":" in normalized.split("/")[0]:
            raise ValueError("unsafe-archive-entry")
    zf.extractall(base)


def _read_pack_manifest(path):
    if os.path.isdir(path):
        manifest_path = os.path.join(path, "manifest.json")
        with open(manifest_path, "r", encoding="utf-8") as handle_file:
            data = json.load(handle_file)
        return _pack_info(data, path)
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        manifest_name = None
        for candidate in names:
            normalized = candidate.replace("\\", "/")
            if normalized.endswith("manifest.json") and normalized.count("/") <= 1:
                manifest_name = candidate
                break
        if manifest_name is None:
            raise ValueError("missing-manifest")
        raw = zf.read(manifest_name).decode("utf-8", "replace")
        return _pack_info(json.loads(raw), path)


def _pack_info(data, path):
    header = data.get("header") or {}
    modules = data.get("modules") or []
    kinds = {m.get("type") for m in modules if isinstance(m, dict)}
    if "data" in kinds:
        kind = "behavior"
    elif "resources" in kinds:
        kind = "resource"
    elif "script" in kinds:
        kind = "behavior"
    else:
        raise ValueError("unknown-pack-type")
    version = header.get("version") or [1, 0, 0]
    if isinstance(version, str):
        version = [int(x) for x in version.split(".") if x.isdigit()] or [1, 0, 0]
    return {
        "uuid": str(header.get("uuid") or ""),
        "name": str(header.get("name") or os.path.basename(path)),
        "version": version,
        "kind": kind,
    }


def apply_addons(data_root, addons_dir, state_path):
    """Install enabled packs and register them on the world.

    Toggles in the app write `enabled`, and this function is what makes that
    change real: it extracts the pack and rewrites world_behavior_packs.json /
    world_resource_packs.json for the selected world. `.mcaddon` bundles are
    expanded into their individual packs first.
    """
    result = {"ok": True, "installed": [], "skipped": []}
    try:
        with open(state_path, "r", encoding="utf-8") as handle_file:
            state = json.load(handle_file)
    except (OSError, ValueError):
        return {"ok": True, "installed": [], "skipped": [], "note": "no-addon-state"}
    world = state.get("world") or "Bedrock level"
    if "/" in world or "\\" in world or world in (".", ".."):
        world = "Bedrock level"
    level = safe_path(data_root, os.path.join("worlds", world))
    active = {"behavior": [], "resource": []}
    staging = os.path.join(addons_dir, ".staging")
    shutil.rmtree(staging, ignore_errors=True)
    for pack in state.get("packs") or []:
        if not isinstance(pack, dict):
            continue
        rel = pack.get("file") or ""
        src = os.path.join(addons_dir, os.path.basename(rel))
        if not os.path.isfile(src):
            result["skipped"].append({"file": rel, "reason": "missing-file"})
            continue
        enabled = bool(pack.get("enabled", True))
        sources = []
        if src.lower().endswith(".mcaddon"):
            bundle_dir = os.path.join(staging, os.path.splitext(os.path.basename(src))[0])
            try:
                with zipfile.ZipFile(src) as zf:
                    _zip_safe(zf, bundle_dir)
            except (ValueError, zipfile.BadZipFile) as error:
                result["skipped"].append({"file": rel, "reason": str(error)})
                continue
            for dirpath, _dirnames, filenames in os.walk(bundle_dir):
                if "manifest.json" in filenames:
                    sources.append(dirpath)
        else:
            sources.append(src)
        if not sources:
            result["skipped"].append({"file": rel, "reason": "no-pack-inside"})
            continue
        for source in sources:
            try:
                info = _read_pack_manifest(source)
            except (ValueError, zipfile.BadZipFile, json.JSONDecodeError) as error:
                result["skipped"].append({"file": rel, "reason": str(error)})
                continue
            folder = info["kind"] + "_packs"
            stem = os.path.splitext(os.path.basename(src))[0]
            if len(sources) > 1:
                stem = "%s-%s" % (stem, info["uuid"][:8])
            dest = safe_path(data_root, os.path.join(folder, stem))
            if enabled:
                shutil.rmtree(dest, ignore_errors=True)
                os.makedirs(dest, exist_ok=True)
                try:
                    if os.path.isdir(source):
                        if os.path.exists(dest):
                            shutil.rmtree(dest)
                        shutil.copytree(source, dest)
                    else:
                        with zipfile.ZipFile(source) as zf:
                            _zip_safe(zf, dest)
                except (ValueError, zipfile.BadZipFile, OSError) as error:
                    result["skipped"].append({"file": rel, "reason": str(error)})
                    continue
                active[info["kind"]].append({"pack_id": info["uuid"], "version": info["version"]})
                result["installed"].append({"file": rel, "kind": info["kind"], "uuid": info["uuid"], "name": info["name"]})
            else:
                shutil.rmtree(dest, ignore_errors=True)
                result["installed"].append({"file": rel, "kind": info["kind"], "uuid": info["uuid"], "name": info["name"], "disabled": True})
    shutil.rmtree(staging, ignore_errors=True)
    if os.path.isdir(level):
        for kind, entries in active.items():
            path = os.path.join(level, "world_%s_packs.json" % kind)
            with open(path, "w", encoding="utf-8") as handle_file:
                json.dump(entries, handle_file, indent=2)
    else:
        result["note"] = "world-not-generated-yet"
    result["world"] = world
    result["enabledCount"] = len(active["behavior"]) + len(active["resource"])
    return result


def import_world(data_root, archive, name):
    if not zipfile.is_zipfile(archive):
        return {"ok": False, "error": "not-a-zip"}
    with zipfile.ZipFile(archive) as zf:
        names = zf.namelist()
        has_level = any(n.replace("\\", "/").endswith("level.dat") for n in names)
        has_db = any(n.replace("\\", "/").split("/")[0] == "db" or "/db/" in n.replace("\\", "/") for n in names)
    if not has_level:
        return {"ok": False, "error": "missing-level-dat"}
    if not has_db:
        return {"ok": False, "error": "missing-world-db"}
    target = safe_path(data_root, os.path.join("worlds", name))
    if os.path.isdir(target):
        return {"ok": False, "error": "world-already-exists"}
    os.makedirs(target, exist_ok=True)
    try:
        with zipfile.ZipFile(archive) as zf:
            _zip_safe(zf, target)
    except ValueError as error:
        shutil.rmtree(target, ignore_errors=True)
        return {"ok": False, "error": str(error)}
    return {"ok": True, "world": name, "path": "worlds/" + name}


TEXT_EXT = {
    ".txt", ".properties", ".json", ".yml", ".yaml", ".toml", ".cfg", ".conf", ".ini",
    ".log", ".md", ".sh", ".bat", ".xml", ".csv", ".mcmeta", ".snbt", ".list",
}
SNAPSHOT_LIMIT = 64 * 1024
SNAPSHOT_MAX_FILES = 150
SNAPSHOT_MAX_BYTES = 3 * 1024 * 1024


def snapshot(root, out_path):
    """Publish small, editable text files as one JSON document.

    This is what makes "edit while the server is stopped" honest: the runner
    publishes the current contents, the app edits the JSON, and the runner
    re-applies it on top of the restored cache before the next start.
    """
    root_real = safe_data_root(root)
    files = {}
    total = 0
    truncated = False
    for dirpath, dirnames, filenames in os.walk(root_real, followlinks=False):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not os.path.islink(os.path.join(dirpath, d))]
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            if os.path.islink(full):
                continue
            ext = os.path.splitext(name)[1].lower()
            if ext not in TEXT_EXT:
                continue
            try:
                size = os.path.getsize(full)
            except OSError:
                continue
            if size > SNAPSHOT_LIMIT or size == 0:
                continue
            if total + size > SNAPSHOT_MAX_BYTES or len(files) >= SNAPSHOT_MAX_FILES:
                truncated = True
                break
            rel = os.path.relpath(full, root_real).replace(os.sep, "/")
            try:
                with open(full, "rb") as handle_file:
                    files[rel] = base64.b64encode(handle_file.read()).decode()
            except OSError:
                continue
            total += size
        if truncated:
            break
    payload = {
        "schema": 1,
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "truncated": truncated,
        "files": files,
    }
    atomic_write_json(out_path, payload)
    return payload


def apply_snapshot(root, snap_path):
    """Apply repository-side edits on top of the restored cache."""
    try:
        with open(snap_path, "r", encoding="utf-8") as handle_file:
            payload = json.load(handle_file)
    except (OSError, ValueError):
        return {"ok": True, "applied": 0}
    applied = 0
    for rel, encoded in (payload.get("files") or {}).items():
        dest = safe_path(root, rel)
        os.makedirs(os.path.dirname(dest) or os.path.realpath(root), exist_ok=True)
        atomic_write_bytes(dest, base64.b64decode(encoded))
        applied += 1
    return {"ok": True, "applied": applied}


def main(argv):
    if len(argv) < 3:
        print("usage: fileops.py <mode> ...", file=sys.stderr)
        return 2
    mode = argv[1]
    if mode == "manifest":
        root, out = argv[2], argv[3]
        root = safe_data_root(root)
        data = manifest(root)
        atomic_write_json(out, data)
        print("manifest %d files" % len(data["files"]))
        return 0
    if mode == "request":
        root, request_path, response_path = argv[2], argv[3], argv[4]
        root = safe_data_root(root)
        try:
            with open(request_path, "r", encoding="utf-8") as handle_file:
                request = json.load(handle_file)
        except (OSError, ValueError):
            request = {}
        request_id = request.get("id")
        try:
            response = handle(root, request)
        except ValueError as error:
            response = _fail(str(error))
        except OSError as error:
            response = _fail("os-error: %s" % error.strerror)
        response["id"] = request_id
        with open(response_path, "w", encoding="utf-8") as handle_file:
            json.dump(response, handle_file, separators=(",", ":"))
        print("request %s -> ok=%s" % (request.get("op"), response.get("ok")))
        return 0
    if mode == "addons":
        data_root, addons_dir, state_path, out = argv[2], argv[3], argv[4], argv[5]
        result = apply_addons(data_root, addons_dir, state_path)
        with open(out, "w", encoding="utf-8") as handle_file:
            json.dump(result, handle_file, separators=(",", ":"))
        print("addons installed=%d skipped=%d" % (len(result["installed"]), len(result["skipped"])))
        return 0
    if mode == "snapshot":
        root, out_path = argv[2], argv[3]
        result = snapshot(root, out_path)
        print("snapshot %d files" % len(result["files"]))
        return 0
    if mode == "apply-snapshot":
        root, snap_path = argv[2], argv[3]
        print("apply-snapshot", apply_snapshot(root, snap_path))
        return 0
    if mode == "import":
        data_root, archive, name, out = argv[2], argv[3], argv[4], argv[5]
        result = import_world(data_root, archive, name)
        with open(out, "w", encoding="utf-8") as handle_file:
            json.dump(result, handle_file, separators=(",", ":"))
        print("import -> %s" % result)
        return 0
    print("unknown mode", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
''';

  static String javaProperties(ServerConfig c) => '''
#Minecraft server properties (managed by NOVA CRAFT)
enable-jmx-monitoring=false
rcon.port=25575
level-seed=${c.seed}
gamemode=${c.gamemode}
enable-command-block=false
enable-query=false
generator-settings={}
enforce-secure-profile=true
level-name=world
motd=${c.motd}
query.port=25565
pvp=${c.pvp}
generate-structures=true
max-chained-neighbor-updates=1000000
difficulty=${c.difficulty}
network-compression-threshold=256
max-tick-time=60000
require-resource-pack=false
use-native-transport=true
max-players=${c.maxPlayers}
online-mode=${c.onlineMode}
enable-status=true
allow-flight=false
initial-disabled-packs=
broadcast-rcon-to-ops=true
view-distance=${c.viewDistance}
server-ip=
resource-pack-prompt=
allow-nether=true
server-port=25565
enable-rcon=false
sync-chunk-writes=true
op-permission-level=4
prevent-proxy-connections=false
hide-online-players=false
entity-broadcast-range-percentage=100
simulation-distance=${c.simulationDistance}
player-idle-timeout=0
force-gamemode=false
rate-limit=0
hardcore=false
white-list=${c.whiteList}
broadcast-console-to-ops=true
spawn-npcs=true
spawn-animals=true
function-permission-level=2
initial-enabled-packs=vanilla
level-type=minecraft\\\\:normal
spawn-monsters=true
enforce-whitelist=${c.whiteList}
spawn-protection=16
max-world-size=29999984
''';

  static String bedrockProperties(ServerConfig c) => '''
server-name=${c.name}
gamemode=${c.gamemode}
force-gamemode=false
difficulty=${c.difficulty}
allow-cheats=false
max-players=${c.maxPlayers}
online-mode=${c.onlineMode}
allow-list=${c.whiteList}
server-port=19132
server-portv6=19133
enable-lan-visibility=false
view-distance=${c.viewDistance}
tick-distance=4
player-idle-timeout=30
max-threads=8
level-name=Bedrock level
level-seed=${c.seed}
default-player-permission-level=member
texturepack-required=false
server-authoritative-movement=server-auth
transport=raknet
''';
}
