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

with open("nova-craft/server.json", "r", encoding="utf-8") as handle:
    cfg = json.load(handle)

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
  python3 - "$text" > "$payload" <<'PY'
import base64, json, os, sys
print(json.dumps({"message": os.environ.get("MSG", "nova: update"),
                  "content": base64.b64encode(sys.argv[1].encode()).decode(),
                  "branch": os.environ.get("REF", "main")}))
PY
  if [ -n "$sha" ] && [ "$sha" != "null" ]; then
    python3 - "$payload" "$sha" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["sha"] = sys.argv[2]
json.dump(d, open(p, "w"))
PY
  fi
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
    "latencyMs": num(latency),
    "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "cycleStartedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(float(started))),
    "conclusion": "",
}, ensure_ascii=False, indent=2))
PY
)"
  if [ "$json" != "$STATUS_LAST" ]; then
    STATUS_LAST="$json"
    MSG="nova: status $phase" REF="$REF" put_file "nova-craft/status.json" "$json" || true
  fi
}

publish_live() {
  local file="$1"
  [ -f "$file" ] || return 0
  local tail_text
  tail_text="$(tail -n 260 "$file" | tail -c 45000)"
  if [ "$tail_text" != "$LIVE_LAST" ]; then
    LIVE_LAST="$tail_text"
    MSG="nova: live log" REF="$REF" put_file "nova-craft/live.log" "$tail_text" || true
  fi
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
  MSG="nova: cycle $conclusion" REF="$REF" put_file "nova-craft/status.json" "$json" || true
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

if [ -f "$INCOMING/world.zip" ]; then
  log "applying imported world"
  if unzip -o -q "$INCOMING/world.zip" -d "$DATA_ABS"; then
    SHA="$(api_content_sha "$INCOMING/world.zip")"
    if [ -n "$SHA" ]; then
      gh api -X DELETE "repos/$REPO/contents/$INCOMING/world.zip" -f message="nova: import applied" -f sha="$SHA" > /dev/null 2>&1 || true
    fi
  else
    log "WARN imported world could not be extracted"
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
  if [ ! -f bedrock_server ]; then
    BURL="$DLURL"
    if [ -z "$BURL" ] || [ "$BURL" = "https://www.minecraft.net/en-us/download/server/bedrock" ]; then
      BURL="$(curl -sL -A "Mozilla/5.0" https://www.minecraft.net/en-us/download/server/bedrock \
        | grep -oE "https://www\.minecraft\.net/bedrockdedicatedserver/bin-linux/[^\"']+\.zip" | head -1)"
    fi
    if [ -z "$BURL" ]; then
      log "ERROR could not resolve the Bedrock download URL"
      publish_cycle_end failure "bedrock-download-url"
      exit 1
    fi
    download "$BURL" bedrock.zip "" || { publish_cycle_end failure "download-failed"; exit 1; }
    unzip -o -q bedrock.zip || { publish_cycle_end failure "bedrock-unzip"; exit 1; }
    chmod +x bedrock_server
    rm -f bedrock.zip
  fi
fi
cd ..

# ------------------------------------------------------------ Playit agent --

start_playit() {
  if [ -z "${PLAYIT_SECRET_KEY:-}" ]; then
    log "PLAYIT_SECRET_KEY is not configured; the server will only be reachable on the runner."
    TUNNEL_STATE=missing
    TUNNEL_MSG="No Playit.gg secret key stored for this repository."
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
  sleep 2
  PLAYIT_PID="$(cat /tmp/nova-playit.pid 2>/dev/null || echo "")"
  if [ -z "$PLAYIT_PID" ] || ! kill -0 "$PLAYIT_PID" 2>/dev/null; then
    TUNNEL_STATE=error
    TUNNEL_MSG="Playit agent exited immediately. Check the secret key and the agent log."
    return 0
  fi
  TUNNEL_STATE=connecting
  TUNNEL_MSG="Playit agent started; waiting for the tunnel to accept connections."
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 6
    if probe_tunnel "$TUNNEL"; then
      TUNNEL_STATE=connected
      TUNNEL_MSG="Public address accepted a TCP connection."
      return 0
    fi
    kill -0 "$PLAYIT_PID" 2>/dev/null || break
  done
  if kill -0 "$PLAYIT_PID" 2>/dev/null; then
    TUNNEL_STATE=connecting
    TUNNEL_MSG="Agent is running but ${TUNNEL:-the tunnel} did not accept a connection yet."
  else
    TUNNEL_STATE=error
    TUNNEL_MSG="Playit agent stopped unexpectedly."
  fi
}

TUNNEL_STATE=unknown
TUNNEL_MSG=""
TUNNEL_ADDR=""
PLAYIT_PID=""
start_playit

# The agent prints the public address it was assigned; read it instead of
# asking the user to type an address that Playit may change.
for _ in 1 2 3 4 5 6; do
  if [ -s "$DATA_ABS/playit.log" ]; then
    FOUND="$(grep -Eho '[a-z0-9-]+\.[a-z0-9-]+\.playit\.gg(:[0-9]+)?' "$DATA_ABS/playit.log" 2>/dev/null | head -1)"
    if [ -n "$FOUND" ]; then TUNNEL_ADDR="$FOUND"; break; fi
  fi
  [ "$TUNNEL_STATE" = "missing" ] && break
  sleep 5
done
export TUNNEL_ADDR

publish_status starting false "server-starting" "" "" "$TUNNEL_STATE" "$TUNNEL_MSG"

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

if ! kill -0 "$SRV_PID" 2>/dev/null && [ "$SERVER_READY" != "true" ]; then
  log "ERROR the server exited before it became ready"
  tail -n 80 "$DATA_ABS/server.log" || true
  publish_live "$DATA_ABS/server.log"
  publish_cycle_end failure "server-crashed"
  exit 1
fi

players_count() {
  local line
  line="$(grep -oE "There are [0-9]+ of a max of [0-9]+ players online" "$DATA_ABS/server.log" 2>/dev/null | tail -1)"
  if [ -n "$line" ]; then echo "$line"; fi
}
parse_players() { echo "$1" | grep -oE "[0-9]+" | head -1; }
parse_max() { echo "$1" | grep -oE "[0-9]+" | sed -n 2p; }

publish_status ready true "server-ready" "$(parse_players "$(players_count)")" "$(parse_max "$(players_count)")" "$TUNNEL_STATE" "$TUNNEL_MSG"
publish_live "$DATA_ABS/server.log"

STOP_FLAG=/tmp/nova-stop
rm -f "$STOP_FLAG"
BACKUP_DONE=false

poll_commands() {
  while kill -0 "$SRV_PID" 2>/dev/null; do
    sleep 12
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
    if probe_tunnel "$TUNNEL"; then
      TUNNEL_STATE=connected
      TUNNEL_MSG="Public address accepted a TCP connection."
    elif [ "$TUNNEL_STATE" = "connected" ]; then
      TUNNEL_STATE=connecting
      TUNNEL_MSG="The public address stopped accepting connections."
    fi
    latency=""
    publish_status ready true "server-ready" "$players" "$(parse_max "$line")" "$TUNNEL_STATE" "$TUNNEL_MSG" "$latency"
    publish_live "$DATA_ABS/server.log"
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
