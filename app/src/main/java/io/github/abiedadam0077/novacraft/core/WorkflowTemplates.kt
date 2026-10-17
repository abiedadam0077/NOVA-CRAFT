package io.github.abiedadam0077.novacraft.core

object WorkflowTemplates {
    fun serverWorkflow(serverId: String): String {
        val raw = """
name: NOVA CRAFT Server
on:
  workflow_dispatch:
    inputs:
      action:
        description: "start runs a full cycle; snapshot restores and re-archives only"
        type: choice
        options: [start, snapshot]
        default: start
      restore_tag:
        description: "Optional backup release tag to restore (empty = latest)"
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
    runs-on: ubuntu-latest
    timeout-minutes: 330
    env:
      GH_TOKEN: __D__{{ github.token }}
      PLAYIT_SECRET_KEY: __D__{{ secrets.PLAYIT_SECRET_KEY }}
    steps:
      - uses: actions/checkout@v4
      - name: Load config
        id: cfg
        run: |
          sudo apt-get update -qq && sudo apt-get install -y -qq jq unzip zip curl > /dev/null
          echo "edition=${'$'}(jq -r .edition nova-craft/server.json)" >> "${'$'}GITHUB_ENV"
          echo "mcversion=${'$'}(jq -r .mcVersion nova-craft/server.json)" >> "${'$'}GITHUB_ENV"
          echo "dlurl=${'$'}(jq -r .downloadUrl nova-craft/server.json)" >> "${'$'}GITHUB_ENV"
          echo "dlsha=${'$'}(jq -r .downloadSha nova-craft/server.json)" >> "${'$'}GITHUB_ENV"
          echo "javamajor=${'$'}(jq -r .javaMajor nova-craft/server.json)" >> "${'$'}GITHUB_ENV"
          echo "memorymb=${'$'}(jq -r .memoryMb nova-craft/server.json)" >> "${'$'}GITHUB_ENV"
          echo "serverid=${'$'}(jq -r .id nova-craft/server.json)" >> "${'$'}GITHUB_ENV"
          mkdir -p server
      - name: Restore latest backup
        run: |
          cd server
          TAG="__D__{{ inputs.restore_tag }}"
          if [ -z "${'$'}TAG" ]; then
            TAG=${'$'}(gh release list --json tagName,createdAt --jq '[.[] | select(.tagName | startswith("backup-__SID__-"))] | sort_by(.createdAt) | last | .tagName // empty')
          fi
          if [ -f ../nova-craft/import/world.zip ]; then
            echo "Applying imported world zip"
            unzip -o -q ../nova-craft/import/world.zip
          fi
          if [ -n "${'$'}TAG" ]; then
            echo "Restoring ${'$'}TAG"
            gh release download "${'$'}TAG" --pattern "world-backup.zip" --pattern "world-backup.sha256" || true
            if [ -f world-backup.zip ]; then
              if [ -f world-backup.sha256 ]; then sha256sum -c world-backup.sha256; fi
              unzip -o -q world-backup.zip
              echo "RESTORED_TAG=${'$'}TAG" >> "${'$'}GITHUB_ENV"
            fi
          else
            echo "No previous backup found; starting fresh."
          fi
      - name: Snapshot only
        if: __D__{{ inputs.action == 'snapshot' }}
        run: |
          cd server
          TS=${'$'}(date -u +%Y%m%dT%H%M%SZ)
          zip -qr world-backup.zip world world_nether world_the_end whitelist.json banned-players.json banned-ips.json ops.json server.properties 2>/dev/null || zip -qr world-backup.zip worlds server.properties allowlist.json permissions.json 2>/dev/null || echo "nothing to archive"
          sha256sum world-backup.zip > world-backup.sha256
          gh release create "backup-__SID__-${'$'}TS" world-backup.zip world-backup.sha256 --title "Snapshot ${'$'}TS" --notes "NOVA CRAFT snapshot (restored: ${'$'}{RESTORED:-none})" || gh release upload "backup-__SID__-${'$'}TS" world-backup.zip world-backup.sha256 --clobber
          echo "snapshot done"
      - uses: actions/setup-java@v4
        if: __D__{{ inputs.action == 'start' && env.edition == 'JAVA' }}
        with:
          distribution: temurin
          java-version: __D__{{ env.javamajor }}
      - name: Download server software
        if: __D__{{ inputs.action == 'start' }}
        run: |
          cd server
          if [ "${'$'}edition" = "JAVA" ]; then
            if [ ! -f server.jar ]; then curl -fL --retry 3 -o server.jar "${'$'}dlurl"; fi
            if [ -n "${'$'}dlsha" ] && [ ${'$'}{#dlsha} -eq 40 ]; then echo "${'$'}dlsha  server.jar" | sha1sum -c - || true; fi
            if [ -n "${'$'}dlsha" ] && [ ${'$'}{#dlsha} -eq 64 ]; then echo "${'$'}dlsha  server.jar" | sha256sum -c - || true; fi
          else
            if [ ! -f bedrock_server ]; then
              BURL=${'$'}(curl -sL -A "Mozilla/5.0" https://www.minecraft.net/en-us/download/server/bedrock | grep -oE "https://www\.minecraft\.net/bedrockdedicatedserver/bin-linux/[^\"']+\.zip" | head -1)
              if [ -z "${'$'}BURL" ]; then BURL="${'$'}dlurl"; fi
              echo "Bedrock download: ${'$'}BURL"
              curl -fL --retry 3 -o bedrock.zip "${'$'}BURL"
              unzip -o -q bedrock.zip
              chmod +x bedrock_server
            fi
            # Preserve our configured server.properties after unzip
            git -C .. checkout -- server.properties 2>/dev/null || true
          fi
      - name: Start Playit agent
        if: __D__{{ inputs.action == 'start' }}
        run: |
          if [ -z "${'$'}PLAYIT_SECRET_KEY" ]; then echo "PLAYIT_SECRET_KEY not set; skipping Playit (LAN/runner only)."; exit 0; fi
          curl -fL --retry 3 -o playit https://github.com/playit-cloud/playit-agent/releases/download/v1.0.10/playit-linux-amd64
          chmod +x playit
          cd server && SECRET_KEY="${'$'}PLAYIT_SECRET_KEY" nohup ../playit > playit.log 2>&1 &
          sleep 5; tail -n 20 server/playit.log || true
      - name: Run server cycle (max ~5h, graceful backup, optional next cycle)
        if: __D__{{ inputs.action == 'start' }}
        run: |
          cat > /tmp/nova-run.sh << 'RUNEOF'
          #!/usr/bin/env bash
          set -u
          cd server
          REPO="${'$'}GITHUB_REPOSITORY"
          SID="${'$'}serverid"
          FIFO=/tmp/nova-stdin; rm -f "${'$'}FIFO"; mkfifo "${'$'}FIFO"
          exec 7<>"${'$'}FIFO"
          STOP_FLAG=/tmp/nova-stop; rm -f "${'$'}STOP_FLAG"
          if [ "${'$'}edition" = "JAVA" ]; then
            java -Xms512M -Xmx${'$'}{memorymb}M -XX:+UseG1GC -jar server.jar nogui < "${'$'}FIFO" > server.log 2>&1 &
          else
            LD_LIBRARY_PATH=. ./bedrock_server < "${'$'}FIFO" > server.log 2>&1 &
          fi
          SRV_PID=${'$'}!
          echo "server pid ${'$'}SRV_PID"
          send_cmd() { printf '%s\n' "${'$'}1" >&7; }
          backup_now() {
            echo "[nova] backup: save + archive"
            send_cmd "save-all flush" || true
            sleep 3
            TS=${'$'}(date -u +%Y%m%dT%H%M%SZ)
            rm -f world-backup.zip world-backup.sha256
            if [ "${'$'}edition" = "JAVA" ]; then
              zip -qr world-backup.zip world world_nether world_the_end whitelist.json banned-players.json banned-ips.json ops.json server.properties 2>/dev/null || true
            else
              zip -qr world-backup.zip worlds server.properties allowlist.json permissions.json 2>/dev/null || true
            fi
            if [ -f world-backup.zip ]; then
              sha256sum world-backup.zip > world-backup.sha256
              gh release create "backup-${'$'}SID-${'$'}TS" world-backup.zip world-backup.sha256 --title "Backup ${'$'}TS" --notes "NOVA CRAFT cycle backup" 2>/dev/null || gh release upload "backup-${'$'}SID-${'$'}TS" world-backup.zip world-backup.sha256 --clobber
              echo "[nova] backup uploaded backup-${'$'}SID-${'$'}TS"
            fi
          }
          poll_commands() {
            while kill -0 ${'$'}SRV_PID 2>/dev/null; do
              sleep 12
              FILES=${'$'}(gh api "repos/${'$'}REPO/contents/nova-craft/commands" --jq '[.[] | select(.type=="file")] | sort_by(.name) | .[].name' 2>/dev/null || true)
              for f in ${'$'}FILES; do
                CMD=${'$'}(gh api "repos/${'$'}REPO/contents/nova-craft/commands/${'$'}f" --jq .content 2>/dev/null | base64 -d 2>/dev/null | tr -d '\r\n')
                SHA=${'$'}(gh api "repos/${'$'}REPO/contents/nova-craft/commands/${'$'}f" --jq .sha 2>/dev/null)
                case "${'$'}CMD" in
                  "nova:stop") touch "${'$'}STOP_FLAG"; send_cmd "say NOVA CRAFT stopping";;
                  "nova:backup") backup_now;;
                  "" ) ;;
                  *) echo "[nova] remote command: ${'$'}CMD"; send_cmd "${'$'}CMD";;
                esac
                gh api -X DELETE "repos/${'$'}REPO/contents/nova-craft/commands/${'$'}f" -f message="nova: consumed command" -f sha="${'$'}SHA" >/dev/null 2>&1 || true
              done
            done
          }
          heartbeat() {
            while kill -0 ${'$'}SRV_PID 2>/dev/null; do
              sleep 600
              NOW=${'$'}(date -u +%Y-%m-%dT%H:%M:%SZ)
              RSS=${'$'}(ps -o rss= -p ${'$'}SRV_PID 2>/dev/null | tr -d ' ' || echo 0)
              jq -n --arg t "${'$'}NOW" --argjson rss "${'$'}{RSS:-0}" --arg sid "${'$'}SID" '{serverId:${'$'}sid, updatedAt:${'$'}t, serverProcessRssKb:${'$'}rss, runnerFreeMb:0}' > /tmp/nova-status.json
              SHA=${'$'}(gh api "repos/${'$'}REPO/contents/nova-craft/status.json" --jq .sha 2>/dev/null || echo "")
              CONTENT=${'$'}(base64 -w0 /tmp/nova-status.json)
              if [ -n "${'$'}SHA" ] && [ "${'$'}SHA" != "null" ]; then
                gh api -X PUT "repos/${'$'}REPO/contents/nova-craft/status.json" -f message="nova: heartbeat" -f content="${'$'}CONTENT" -f sha="${'$'}SHA" >/dev/null 2>&1 || true
              else
                gh api -X PUT "repos/${'$'}REPO/contents/nova-craft/status.json" -f message="nova: heartbeat" -f content="${'$'}CONTENT" >/dev/null 2>&1 || true
              fi
            done
          }
          poll_commands & POLL_PID=${'$'}!
          heartbeat & HB_PID=${'$'}!
          START=${'$'}(date +%s); MAXSEC=17400
          while kill -0 ${'$'}SRV_PID 2>/dev/null; do
            if [ -f "${'$'}STOP_FLAG" ]; then echo "[nova] stop requested"; break; fi
            NOW=${'$'}(date +%s); if [ ${'$'}((NOW-START)) -ge ${'$'}MAXSEC ]; then echo "[nova] cycle limit reached"; break; fi
            sleep 10
          done
          backup_now || true
          send_cmd "stop" || true
          for i in ${'$'}(seq 1 30); do kill -0 ${'$'}SRV_PID 2>/dev/null || break; sleep 2; done
          kill ${'$'}SRV_PID 2>/dev/null || true
          kill ${'$'}POLL_PID ${'$'}HB_PID 2>/dev/null || true
          tail -n 100 server.log || true
          if [ ! -f "${'$'}STOP_FLAG" ]; then
            AUTO=${'$'}(jq -r .autoRestart nova-craft/server.json 2>/dev/null || echo true)
            if [ "${'$'}AUTO" = "true" ]; then
              echo "[nova] dispatching next cycle"
              gh workflow run novacraft-server.yml --ref main -f action=start || true
            fi
          fi
          RUNEOF
          chmod +x /tmp/nova-run.sh
          /tmp/nova-run.sh
"""
        return raw.replace("__SID__", serverId).replace("__D__", "$")
    }

    fun javaProperties(c: ServerConfig): String = """
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
level-type=minecraft\:normal
spawn-monsters=true
enforce-whitelist=${c.whiteList}
spawn-protection=16
max-world-size=29999984
""".trimIndent()

    fun bedrockProperties(c: ServerConfig): String = """
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
""".trimIndent()
}
