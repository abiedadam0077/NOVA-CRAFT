import 'models.dart';

/// The GitHub Actions workflow that actually runs a NOVA CRAFT server.
///
/// Design notes (these were real bugs in the previous revision):
/// * `if: env.X` cannot see variables written to `$GITHUB_ENV` by an earlier
///   step, so config values are exposed as step *outputs* instead.
/// * The job timeout (330 min) is shorter than GitHub's 6 h hard limit so the
///   graceful backup + next-cycle dispatch always have time to run.
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
    timeout-minutes: 330
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
import sys

with open("nova-craft/server.json", "r", encoding="utf-8") as handle:
    cfg = json.load(handle)


def truthy(value):
    return "true" if value else "false"


def write_properties():
    """Regenerate server.properties (and eula.txt) from server.json.

    The Actions cache restores the whole data folder, so values committed in the
    repository could otherwise be overwritten by an older cached copy. Writing
    them again after the restore makes the app's settings authoritative.
    """
    root = cfg.get("dataPath") or "server"
    os.makedirs(root, exist_ok=True)
    bedrock = (cfg.get("edition") or "JAVA").upper() == "BEDROCK"
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
    "sid": cfg.get("id", ""),
    "edition": cfg.get("edition", "JAVA"),
    "javamajor": str(cfg.get("javaMajor", 21)),
    "data": cfg.get("dataPath") or "server",
    "software": cfg.get("software", "VANILLA"),
    "memory": str(cfg.get("memoryMb", 4096)),
    "eula": "true" if cfg.get("eulaAccepted") else "false",
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
TUNNEL="$(python3 -c 'import json;print(json.load(open("nova-craft/server.json")).get("playitAddress",""))')"
AUTORESTART="$(python3 -c 'import json;print("true" if json.load(open("nova-craft/server.json")).get("autoRestart",True) else "false")')"
MAXSEC=17100
JOB_STARTED=$(date +%s)
PHASE=unknown
STATUS_LAST=""
LIVE_LAST=""
PLAYIT_PID=""
SRV_PID=""

mkdir -p "$DATA"
cd "$DATA" || exit 1
DATA_ABS="$(pwd)"
cd ..

log() { echo "[nova] $*"; }

# ---------------------------------------------------------------- utilities --

api_content_sha() {
  gh api "repos/$REPO/contents/$1" --jq .sha 2>/dev/null || echo ""
}

api_content_text() {
  gh api "repos/$REPO/contents/$1" --jq .content 2>/dev/null | base64 -d 2>/dev/null || true
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
  if ! gh api -X PUT "repos/$REPO/contents/$path" --input "$payload" > /dev/null 2>&1; then
    log "WARN could not publish $path"
    rm -f "$payload"
    return 1
  fi
  rm -f "$payload"
  return 0
}

publish_status() {
  local phase="$1" ready="$2" reason="${3:-}" players="${4:-}" pmax="${5:-}" tunnel="${6:-unknown}" tunnel_msg="${7:-}" latency="${8:-}"
  local json
  json="$(python3 - "$phase" "$ready" "$reason" "$players" "$pmax" "$tunnel" "$tunnel_msg" "$latency" "$SRV_PID" "$MCV" "$JOB_STARTED" <<'PY'
import json, os, sys, time
phase, ready, reason, players, pmax, tunnel, tmsg, latency, pid, mcv, started = sys.argv[1:12]
def num(v):
    try:
        return int(v)
    except Exception:
        return None
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
    "tunnelAddress": os.environ.get("TUNNEL_ADDR", ""),
    "tunnelName": os.environ.get("TUNNEL_NAME", ""),
    "tunnelProtocol": os.environ.get("TUNNEL_PROTO", ""),
    "tunnelOfflineReasons": [x for x in [os.environ.get("TUNNEL_ISSUE", "")] if x],
    "agentId": os.environ.get("AGENT_ID", ""),
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
  # A structured file manifest plus a bounded snapshot of editable text files.
  python3 nova-craft/fileops.py manifest "$DATA_ABS" "$DATA_ABS/../nova-craft/files/manifest.json" > /dev/null 2>&1 || true
  if [ -f nova-craft/files/manifest.json ]; then
    put_file "nova-craft/files/manifest.json" "$(cat nova-craft/files/manifest.json)" "nova: file manifest" || true
  fi
  python3 nova-craft/fileops.py snapshot "$DATA_ABS" "$DATA_ABS/../nova-craft/snapshot.json" > /dev/null 2>&1 || true
  if [ -f nova-craft/snapshot.json ]; then
    put_file "nova-craft/snapshot.json" "$(cat nova-craft/snapshot.json)" "nova: config snapshot" || true
  fi
}

# File operations requested from the app. Applied immediately while a cycle is
# running, so the Files tab is not limited to "next start".
apply_file_request() {
  local sha payload_text
  sha="$(api_content_sha "nova-craft/files/request.json")"
  [ -n "$sha" ] || return 0
  payload_text="$(gh api "repos/$REPO/contents/nova-craft/files/request.json" --jq .content 2>/dev/null | base64 -d 2>/dev/null)"
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
    -f message="nova: file request consumed" -f sha="$sha" > /dev/null 2>&1 || true
  publish_files
}

publish_cycle_end() {
  local conclusion="$1" reason="$2"
  local json
  json="$(python3 - "$conclusion" "$reason" "$MCV" "$JOB_STARTED" <<'PY'
import json, sys, time
conclusion, reason, mcv, started = sys.argv[1:5]
print(json.dumps({
    "schema": 2,
    "serverId": json.load(open("nova-craft/server.json"))["id"],
    "phase": "stopped" if conclusion == "success" else "failed",
    "ready": False,
    "reason": reason,
    "conclusion": conclusion,
    "version": mcv,
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
  # Returns 0 only when the public address really resolves and accepts TCP,
  # and only while the agent process is alive.
  local address="$1"
  [ -n "$address" ] || return 1
  [ -n "$PLAYIT_PID" ] || return 1
  kill -0 "$PLAYIT_PID" 2>/dev/null || return 1
  python3 - "$address" <<'PY'
import socket, sys
address = sys.argv[1].replace("tcp://", "").replace("udp://", "")
host, _, port = address.rpartition(":")
if not host:
    host, port = address, "25565"
try:
    with socket.create_connection((host, int(port)), timeout=6):
        sys.exit(0)
except Exception:
    sys.exit(1)
PY
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
RESTORE_TAG="${NOVA_RESTORE_TAG:-}"
if [ -z "$RESTORE_TAG" ]; then
  RESTORE_TAG="$(gh release list --repo "$REPO" --limit 60 --json tagName,createdAt \
      --jq '[.[] | select(.tagName | startswith("backup-'"$SID"'-"))] | sort_by(.createdAt) | last | .tagName // empty' 2>/dev/null || true)"
fi
if [ -n "$RESTORE_TAG" ]; then
  log "restoring release $RESTORE_TAG"
  TMPD="$(mktemp -d)"
  if gh release download "$RESTORE_TAG" --repo "$REPO" --pattern "world-backup.zip" --dir "$TMPD" 2>/dev/null; then
    if gh release download "$RESTORE_TAG" --repo "$REPO" --pattern "world-backup.sha256" --dir "$TMPD" 2>/dev/null; then
      (cd "$TMPD" && sha256sum -c world-backup.sha256) || log "WARN backup checksum mismatch"
    fi
    unzip -o -q "$TMPD/world-backup.zip" -d "$DATA_ABS" && log "restored $RESTORE_TAG"
  else
    log "WARN could not download $RESTORE_TAG; keeping cached data"
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
      gh api -X DELETE "repos/$REPO/contents/$INCOMING/world.zip" -f message="nova: import applied" -f sha="$SHA" > /dev/null 2>&1 || true
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

backup_now() {
  local phase_label="$1"
  local ts tag
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  tag="backup-$SID-$ts"
  rm -f "$DATA_ABS/world-backup.zip" "$DATA_ABS/world-backup.sha256"
  if [ "$EDITION" = "JAVA" ]; then
    (cd "$DATA_ABS" && zip -qr world-backup.zip world world_nether world_the_end \
        whitelist.json banned-players.json banned-ips.json ops.json server.properties 2>/dev/null || true)
  else
    (cd "$DATA_ABS" && zip -qr world-backup.zip worlds server.properties allowlist.json permissions.json 2>/dev/null || true)
  fi
  if [ ! -f "$DATA_ABS/world-backup.zip" ]; then
    log "ERROR nothing to archive yet"
    return 1
  fi
  (cd "$DATA_ABS" && sha256sum world-backup.zip > world-backup.sha256)
  if ! gh release create "$tag" "$DATA_ABS/world-backup.zip" "$DATA_ABS/world-backup.sha256" \
        --repo "$REPO" --title "Backup $ts" \
        --notes "NOVA CRAFT $phase_label backup (restored: ${RESTORE_TAG:-cache})"; then
    log "WARN release create failed, retrying upload"
    gh release upload "$tag" "$DATA_ABS/world-backup.zip" "$DATA_ABS/world-backup.sha256" --repo "$REPO" --clobber || return 1
  fi
  log "backup published $tag"
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
cd ..

# ------------------------------------------------------------ Playit agent --

start_playit() {
  TUNNEL_STATE=missing
  TUNNEL_MSG="No Playit.gg agent secret is stored for this repository."
  TUNNEL_ADDR=""
  TUNNEL_NAME=""
  TUNNEL_PROTO=""
  TUNNEL_ISSUE=""
  AGENT_ID=""
  if [ -z "${PLAYIT_SECRET_KEY:-}" ]; then
    return 0
  fi

  local url="https://github.com/playit-cloud/playit-agent/releases/download/v1.0.10/playit-linux-amd64"
  if [ ! -x playit ]; then
    curl -fL --retry 3 -o playit.tmp "$url" || { TUNNEL_STATE=error; TUNNEL_MSG="Playit agent download failed"; return 0; }
    if [ ! -s playit.tmp ]; then TUNNEL_STATE=error; TUNNEL_MSG="Playit agent download was empty"; return 0; fi
    chmod +x playit.tmp
    mv playit.tmp playit
  fi

  ( cd "$DATA_ABS" && SECRET_KEY="$PLAYIT_SECRET_KEY" nohup ../playit > playit.log 2>&1 & echo $! > /tmp/nova-playit.pid )
  sleep 3
  PLAYIT_PID="$(cat /tmp/nova-playit.pid 2>/dev/null || echo "")"
  if [ -z "$PLAYIT_PID" ] || ! kill -0 "$PLAYIT_PID" 2>/dev/null; then
    TUNNEL_STATE=error
    TUNNEL_MSG="The Playit agent exited immediately. Rotate the secret in the Playit dashboard and save it again."
    return 0
  fi
  TUNNEL_STATE=connecting
  TUNNEL_MSG="The agent is running; asking Playit for the tunnel."

  # ---------------------------------------------------------- official API --
  # Same agent endpoints the official agent/plugin use; the secret only ever
  # travels in the Authorization header of these two calls.
  playit_api() {
    curl -sS --max-time 25 -X POST "https://api.playit.gg$1" \
      -H "Authorization: Agent-Key $PLAYIT_SECRET_KEY" \
      -H "Content-Type: application/json" -d "$2"
  }
  refresh_tunnel() {
    rm -f /tmp/nova-rundata.json /tmp/nova-tunnel.env
    playit_api /v1/agents/rundata '{}' > /tmp/nova-rundata.json 2>/dev/null || true
    [ -s /tmp/nova-rundata.json ] || return 1
    python3 nova-craft/playit.py parse /tmp/nova-rundata.json /tmp/nova-tunnel.env "$EDITION" > /dev/null || return 1
    . /tmp/nova-tunnel.env
    [ -n "$TUNNEL_Q_MSG" ] && TUNNEL_MSG="$TUNNEL_Q_MSG"
    return 0
  }

  if ! refresh_tunnel; then
    TUNNEL_STATE=error
    TUNNEL_MSG="The Playit API did not answer. The agent may be offline or the secret invalid."
    return 0
  fi

  # ---------------------------------------------------- create once if needed
  if [ "$TUNNEL_STATE" = "missing" ] && [ -n "$AGENT_ID" ] && [ "${NOVA_ALLOW_TUNNEL_CREATE:-true}" = "true" ]; then
    if [ "$EDITION" = "BEDROCK" ]; then TTYPE=minecraft-bedrock; else TTYPE=minecraft-java; fi
    log "no $TTYPE tunnel yet; creating one through the agent API"
    BODY="$(python3 nova-craft/playit.py body "$AGENT_ID" "$TTYPE" "NOVA $SID")"
    playit_api /v1/tunnels/create "$BODY" > /tmp/nova-create.json 2>/dev/null || true
    CREATE_MSG="$(python3 nova-craft/playit.py explain /tmp/nova-create.json 2>/dev/null || echo unknown)"
    log "playit create -> $CREATE_MSG"
    if [ "$CREATE_MSG" != "created" ]; then
      TUNNEL_STATE=missing
      TUNNEL_MSG="Playit refused automatic tunnel creation ($CREATE_MSG). Create a Minecraft tunnel for this agent at playit.gg/account/tunnels, then start again."
      return 0
    fi
    sleep 8
    refresh_tunnel || true
  fi

  # ----------------------------- verify: real TCP connect while agent is alive
  if [ -n "$TUNNEL_ADDR" ] && [ "$TUNNEL_STATE" = "allocated" ]; then
    for _ in 1 2 3 4 5 6 7 8; do
      if probe_tunnel "$TUNNEL_ADDR"; then
        TUNNEL_STATE=connected
        TUNNEL_MSG="Playit reports $TUNNEL_ADDR and it accepted a TCP connection."
        return 0
      fi
      kill -0 "$PLAYIT_PID" 2>/dev/null || break
      sleep 6
    done
    TUNNEL_STATE=allocated
    TUNNEL_MSG="Playit reports $TUNNEL_ADDR but nothing answered on it yet."
    return 0
  fi

  if [ "$TUNNEL_STATE" = "disabled" ]; then
    TUNNEL_MSG="Playit reports this tunnel as disabled (${TUNNEL_ISSUE:-no reason given})."
  elif [ -z "$TUNNEL_MSG" ]; then
    TUNNEL_MSG="No public address is available for this tunnel yet."
  fi
}

TUNNEL_STATE=unknown
TUNNEL_MSG=""
TUNNEL_ADDR=""
TUNNEL_NAME=""
TUNNEL_PROTO=""
TUNNEL_ISSUE=""
AGENT_ID=""
PLAYIT_PID=""
start_playit

export TUNNEL_STATE TUNNEL_MSG TUNNEL_ADDR TUNNEL_NAME TUNNEL_PROTO TUNNEL_ISSUE AGENT_ID

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
cd ..
log "server pid $SRV_PID"

send_cmd() { printf '%s\n' "$1" >&7 2>/dev/null || true; }

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
  publish_live "$DATA_ABS/server.log"
  publish_cycle_end failure "server-crashed"
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

publish_status ready true "server-ready" "$(parse_players "$(players_count)")" "$(parse_max "$(players_count)")" "$TUNNEL_STATE" "$TUNNEL_MSG"
publish_live "$DATA_ABS/server.log"
publish_files

STOP_FLAG=/tmp/nova-stop
rm -f "$STOP_FLAG"
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
        "nova:backup") log "backup requested from the app";;
        "") : ;;
        *) log "command: $cmd"; send_cmd "$cmd";;
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
    local players line latency
    line="$(players_count)"
    players="$(parse_players "$line")"
    # Probe the address Playit actually reported, never the (often empty)
    # address configured by hand.
    if probe_tunnel "${TUNNEL_ADDR:-$TUNNEL}"; then
      TUNNEL_STATE=connected
      TUNNEL_MSG="Public address accepted a TCP connection."
    elif [ "$TUNNEL_STATE" = "connected" ]; then
      TUNNEL_STATE=connecting
      TUNNEL_MSG="The public address stopped accepting connections."
    fi
    latency=""
    publish_status ready true "server-ready" "$players" "$(parse_max "$line")" "$TUNNEL_STATE" "$TUNNEL_MSG" "$latency"
    publish_live "$DATA_ABS/server.log"
    if [ $(( $(date +%s) - LAST_FILES_PUBLISH )) -ge 300 ]; then
      LAST_FILES_PUBLISH=$(date +%s)
      publish_files
    fi
  done
}

poll_commands & POLL_PID=$!
heartbeat & HB_PID=$!

while kill -0 "$SRV_PID" 2>/dev/null; do
  if [ -f "$STOP_FLAG" ]; then log "stop requested from the app"; break; fi
  if [ $(( $(date +%s) - JOB_STARTED )) -ge "$MAXSEC" ]; then log "cycle time limit reached"; break; fi
  sleep 10
done

kill "$POLL_PID" "$HB_PID" 2>/dev/null || true

# Safe shutdown: freeze writes, flush, archive, then stop.
publish_status stopping false "stopping"
send_cmd "save-off"
send_cmd "save-all flush"
sleep 6
cd "$DATA_ABS" || true
if backup_now "cycle"; then BACKUP_DONE=true; fi
cd ..
send_cmd "save-on"
send_cmd "stop"
for _ in $(seq 1 45); do kill -0 "$SRV_PID" 2>/dev/null || break; sleep 2; done
if kill -0 "$SRV_PID" 2>/dev/null; then log "server did not stop in time; killing"; kill -9 "$SRV_PID" 2>/dev/null || true; fi

exec 7>&- 2>/dev/null || true
if [ -n "$PLAYIT_PID" ]; then kill "$PLAYIT_PID" 2>/dev/null || true; fi

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
"""Playit.gg agent-API helper for the NOVA CRAFT runner.

Playit's public web API requires an account session (Playit Premium partner
keys for some calls), but every agent authenticates with its own secret via
`Authorization: Agent-Key <secret>`. These are the same documented endpoints
the official agent and official Minecraft plugin use:

  POST https://api.playit.gg/v1/agents/rundata
  POST https://api.playit.gg/v1/tunnels/create
  POST https://api.playit.gg/v1/tunnels/list

The helper never prints the secret.

modes
  parse   <rundata.json> <out.env> [edition]  -> shell assignments
  body    <agent_id> <type> <name>            -> create request JSON
  explain <create.json>                       -> human readable failure code
"""
import json
import shlex
import sys

TYPES = {"java": "minecraft-java", "bedrock": "minecraft-bedrock"}


def load(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}


def unwrap(raw):
    """Playit wraps results as {status, data} / {status, fail} / {status, error}."""
    if not isinstance(raw, dict):
        return {}, "invalid-response"
    status = raw.get("status")
    if status in ("fail", "error"):
        detail = raw.get("fail") or raw.get("error") or status
        return {}, detail if isinstance(detail, str) else json.dumps(detail)
    data = raw.get("data")
    if isinstance(data, dict):
        return data, ""
    if isinstance(raw.get("success"), dict):
        return raw["success"], ""
    return raw, ""


def pick_tunnel(tunnels, edition):
    want = TYPES.get((edition or "java").lower(), "minecraft-java")
    for tunnel in tunnels:
        if (tunnel.get("tunnel_type") or "") == want:
            return tunnel
    return None


def parse(argv):
    raw = load(argv[0])
    out_path = argv[1]
    edition = argv[2] if len(argv) > 2 else "java"
    data, error = unwrap(raw)
    tunnels = [t for t in (data.get("tunnels") or []) if isinstance(t, dict)]
    chosen = pick_tunnel(tunnels, edition)
    values = {
        "AGENT_ID": str(data.get("agent_id") or ""),
        "TUNNEL_STATE": "missing",
        "TUNNEL_Q_MSG": "",
    }
    if error:
        values["TUNNEL_STATE"] = "error"
        values["TUNNEL_Q_MSG"] = "Playit API answered with: " + error[:200]
    elif chosen:
        reason = chosen.get("disabled_reason")
        if isinstance(reason, dict):
            reason = reason.get("type") or json.dumps(reason)
        values["TUNNEL_STATE"] = "disabled" if reason else "allocated"
        values["TUNNEL_ADDR"] = str(chosen.get("display_address") or "")
        values["TUNNEL_NAME"] = str(chosen.get("name") or "")
        values["TUNNEL_PROTO"] = str(chosen.get("port_type") or "")
        values["TUNNEL_ISSUE"] = str(reason or "")
        if not values["TUNNEL_ADDR"]:
            values["TUNNEL_STATE"] = "missing"
            values["TUNNEL_Q_MSG"] = "Playit has not allocated a public address for this tunnel yet."
    else:
        count = len(tunnels)
        values["TUNNEL_Q_MSG"] = (
            "This agent has %d tunnel(s) but none of type %s." % (count, TYPES.get(edition, "minecraft-java"))
            if count
            else "This Playit agent has no tunnel yet."
        )
    with open(out_path, "w", encoding="utf-8") as handle:
        for key, value in values.items():
            handle.write("%s=%s\n" % (key, shlex.quote(value)))
    print("tunnel state: %s" % values["TUNNEL_STATE"])
    return 0


def body(argv):
    agent_id, tunnel_type, name = argv[0], argv[1], argv[2]
    local_port = "19132" if tunnel_type == TYPES["bedrock"] else "25565"
    print(json.dumps({
        "name": name[:20],
        "ports": {"type": "tunnel-type", "details": tunnel_type},
        "origin": {
            "type": "agent",
            "data": {
                "agent_id": agent_id,
                "config": {"fields": [
                    {"name": "local_ip", "value": "127.0.0.1"},
                    {"name": "local_port", "value": local_port},
                ]},
            },
        },
        "enabled": True,
    }))
    return 0


def explain(argv):
    raw = load(argv[0])
    data, error = unwrap(raw)
    if error:
        print(error)
    elif data.get("id") or data.get("tunnel_id"):
        print("created")
    else:
        print(json.dumps(raw)[:200])
    return 0


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    mode = argv[1]
    if mode == "parse":
        return parse(argv[2:])
    if mode == "body":
        return body(argv[2:])
    if mode == "explain":
        return explain(argv[2:])
    print("unknown mode", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
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
import shutil
import sys
import time
import zipfile

MAX_READ = 700 * 1024
MAX_MANIFEST_ENTRIES = 4000
SKIP_DIRS = {"libraries", "versions", ".fabric", "cache", ".cache", "tmp", "crash-reports"}


def safe_path(root, rel):
    root_real = os.path.realpath(root)
    rel = (rel or "").replace("\\", "/").strip()
    rel = rel.lstrip("/")
    if not rel or rel == ".":
        return root_real
    candidate = os.path.realpath(os.path.join(root_real, rel))
    if candidate != root_real and not candidate.startswith(root_real + os.sep):
        raise ValueError("path-outside-root")
    return candidate


def manifest(root):
    root_real = os.path.realpath(root)
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
        os.makedirs(os.path.dirname(target) or root, exist_ok=True)
        tmp = target + ".nova-tmp"
        with open(tmp, "wb") as handle_file:
            handle_file.write(data)
        os.replace(tmp, target)
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
    root_real = os.path.realpath(root)
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
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as handle_file:
        json.dump(payload, handle_file, separators=(",", ":"))
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
        os.makedirs(os.path.dirname(dest) or root, exist_ok=True)
        with open(dest, "wb") as handle_file:
            handle_file.write(base64.b64decode(encoded))
        applied += 1
    return {"ok": True, "applied": applied}


def main(argv):
    if len(argv) < 3:
        print("usage: fileops.py <mode> ...", file=sys.stderr)
        return 2
    mode = argv[1]
    if mode == "manifest":
        root, out = argv[2], argv[3]
        os.makedirs(root, exist_ok=True)
        data = manifest(root)
        with open(out, "w", encoding="utf-8") as handle_file:
            json.dump(data, handle_file, separators=(",", ":"))
        print("manifest %d files" % len(data["files"]))
        return 0
    if mode == "request":
        root, request_path, response_path = argv[2], argv[3], argv[4]
        os.makedirs(root, exist_ok=True)
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
