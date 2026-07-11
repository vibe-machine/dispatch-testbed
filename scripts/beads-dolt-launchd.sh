#!/bin/bash
set -uo pipefail

# ── scripts/beads-dolt-launchd.sh ───────────────────────────────────
# Install (and, if needed, first-time populate) the per-project
# launchd-managed Dolt sql-server that beads connects to in server mode.
#
# WHY THIS EXISTS
# The fleet runs beads' Dolt backend as a persistent `dolt sql-server`
# managed by launchd — one per project, on a fixed port — rather than
# bd's ephemeral auto-started server. bd then connects to it as an
# *externally-managed* server via the port file (.beads/dolt-server.port).
# This script reproduces that on a new machine in one shot.
#
# THE FRESH-BOOTSTRAP CAVEAT (important)
# Current bd (1.0.4 AND 1.0.5) CANNOT create a server-mode database from
# scratch: `bd bootstrap`/`bd init` against a sql-server dies with
#   "commit init: dolt commit: Error 1105: nothing to commit"
# regardless of dolt version (2.0.8/2.1.0). The fleet's existing DBs were
# created under an older bd and grandfathered in. So when beads_one does
# not yet exist, this script populates it the only way that works:
#   init schema in EMBEDDED mode  ->  bd import the JSONL  ->  move the
#   resulting repo into the server layout (.beads/dolt/beads_one).
#
# Idempotent: re-running with a healthy DB only (re)installs the agent.
#
# Usage:
#   scripts/beads-dolt-launchd.sh [--port N] [--reinstall]
# Env overrides:
#   BEADS_DOLT_PORT (default 3307), BEADS_DOLT_REMOTESAPI_PORT (default 8080)

PORT="${BEADS_DOLT_PORT:-3317}"
REMOTESAPI_PORT="${BEADS_DOLT_REMOTESAPI_PORT:-8091}"
REINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --reinstall) REINSTALL=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DATA_DIR="$REPO_ROOT/.beads/dolt"
PLIST="$HOME/Library/LaunchAgents/com.vibe-machine.dispatch-testbed-dolt.plist"
LABEL="com.vibe-machine.dispatch-testbed-dolt"
DOLT="$(command -v dolt || echo /opt/homebrew/bin/dolt)"
BD="$(command -v bd || echo /opt/homebrew/bin/bd)"

# Custom issue types that must be registered for fresh imports (the `wave`
# dispatch type is not a bd builtin; chicken/egg means it has to come in as
# an env var on the import that creates the DB, not via `bd config set`).
CUSTOM_TYPES="wave,decision"

log() { printf '  %s\n' "$*"; }

set_dolt_mode() {
  local mode="$1"
  /usr/bin/python3 - "$REPO_ROOT/.beads/metadata.json" "$mode" <<'PY'
import json, sys
path, mode = sys.argv[1:]
data = json.load(open(path))
data["dolt_mode"] = mode
data["dolt_database"] = "dtb"
json.dump(data, open(path, "w"), indent=2)
PY
}

stop_data_dir_servers() {
  local pid cwd
  for pid in $(pgrep -f 'dolt sql-server' 2>/dev/null || true); do
    cwd="$(lsof -a -d cwd -p "$pid" -Fn 2>/dev/null | sed -n 's/^n//p')"
    if [ "$cwd" = "$DATA_DIR" ]; then
      kill "$pid" 2>/dev/null || true
    fi
  done
}

stop_server() {
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
  sleep 1
  stop_data_dir_servers
  pkill -f "dolt sql-server.*--port $PORT" 2>/dev/null || true
  pkill -f "dolt sql-server.*-P $PORT" 2>/dev/null || true
  sleep 1
}

write_plist() {
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$DOLT</string>
    <string>sql-server</string>
    <string>--host</string>
    <string>127.0.0.1</string>
    <string>--port</string>
    <string>$PORT</string>
    <string>--remotesapi-port</string>
    <string>$REMOTESAPI_PORT</string>
    <string>--data-dir</string>
    <string>$DATA_DIR</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$DATA_DIR</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$DATA_DIR/sql-server.log</string>
  <key>StandardErrorPath</key>
  <string>$DATA_DIR/sql-server.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
PLIST_EOF
}

start_server() {
  printf '%s' "$PORT" > "$REPO_ROOT/.beads/dolt-server.port"
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
  stop_data_dir_servers
  pkill -f "dolt sql-server.*--port $PORT" 2>/dev/null || true
  pkill -f "dolt sql-server.*-P $PORT" 2>/dev/null || true
  sleep 1
  launchctl bootstrap "gui/$UID" "$PLIST"
  sleep 3
}

db_has_data() {
  # beads_one exists as a subdir repo AND bd can query it
  [ -d "$DATA_DIR/dtb/.dolt" ] && "$BD" -C "$REPO_ROOT" stats >/dev/null 2>&1
}

populate_fresh() {
  log "dtb not populated — running embedded-init -> import -> migrate"
  stop_server
  rm -rf "$REPO_ROOT/.beads/dolt" "$REPO_ROOT/.beads/embeddeddolt"
  set_dolt_mode embedded
  if git -C "$REPO_ROOT" ls-remote --exit-code origin refs/dolt/data >/dev/null 2>&1; then
    # Existing repository: preserve the shared Dolt lineage.
    "$BD" -C "$REPO_ROOT" bootstrap
  else
    # First publication: initialize in embedded mode because current bd cannot
    # initialize a brand-new database through sql-server.
    (
      cd "$REPO_ROOT"
      BD_TYPES_CUSTOM="$CUSTOM_TYPES" "$BD" init --reinit-local --prefix dtb --non-interactive >/dev/null
    )
    BD_TYPES_CUSTOM="$CUSTOM_TYPES" "$BD" -C "$REPO_ROOT" import -i "$REPO_ROOT/.beads/issues.jsonl"
    "$BD" -C "$REPO_ROOT" dolt commit >/dev/null 2>&1 || true
  fi
  # Migrate the embedded repo into the server layout.
  stop_server
  mkdir -p "$DATA_DIR"
  if [ -d "$REPO_ROOT/.beads/dolt/.dolt" ]; then
    mv "$REPO_ROOT/.beads/dolt" "$REPO_ROOT/.beads/dolt-embedded"
    mkdir -p "$DATA_DIR"
    mv "$REPO_ROOT/.beads/dolt-embedded" "$DATA_DIR/dtb"
  elif [ -d "$REPO_ROOT/.beads/embeddeddolt/dtb" ]; then
    mv "$REPO_ROOT/.beads/embeddeddolt/dtb" "$DATA_DIR/dtb"
  fi
  rm -rf "$REPO_ROOT/.beads/embeddeddolt"
}

echo "beads dolt launchd installer  (port $PORT, data-dir $DATA_DIR)"

if [ "$REINSTALL" = 1 ] || ! db_has_data; then
  # Need the server up to test/populate.
  write_plist
  start_server
  if ! db_has_data; then
    populate_fresh
    write_plist
    start_server
  fi
else
  write_plist
  start_server
fi

# launchd owns the durable server after any embedded bootstrap work.
set_dolt_mode server
"$DOLT" --host 127.0.0.1 --port "$PORT" --no-tls sql -q \
  "use dtb; insert into config (\`key\`, value) values ('issue_prefix', 'dtb') on duplicate key update value = 'dtb';" \
  >/dev/null
if ! "$BD" -C "$REPO_ROOT" show dtb-1 >/dev/null 2>&1; then
  BD_TYPES_CUSTOM="$CUSTOM_TYPES" "$BD" -C "$REPO_ROOT" import -i "$REPO_ROOT/.beads/issues.jsonl"
fi

# Register custom types in the DB so writes don't need the env var.
"$BD" -C "$REPO_ROOT" config set types.custom "$CUSTOM_TYPES" >/dev/null 2>&1 || true

echo
if db_has_data; then
  log "✓ server up on $PORT; dtb reachable"
  "$BD" -C "$REPO_ROOT" stats 2>/dev/null | grep -iE "Total Issues" || true
  log "note: 'bd dolt status' will say 'not running' (launchd owns the process);"
  log "      'bd dolt show' is the real check and should say 'Server connection OK'."
else
  echo "  ✗ beads_one still not reachable — check $DATA_DIR/sql-server.log" >&2
  exit 1
fi
