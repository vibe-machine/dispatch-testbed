#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
set +e
swift test --package-path "$ROOT" "$@"
result=$?
set -e

runtime_home="${AGENT_RUNTIME_HOME:-${CODEX_HOME:-}}"
if [ -n "$runtime_home" ]; then
  mkdir -p "$runtime_home"
  finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  /usr/bin/python3 - "$runtime_home/test-evidence.json" "$result" "$started_at" "$finished_at" <<'PY'
import json, sys
path, result, started, finished = sys.argv[1:]
with open(path, "w") as stream:
    json.dump({
        "schema_version": 1,
        "command": "mise run test",
        "exit_code": int(result),
        "started_at": started,
        "finished_at": finished,
    }, stream, indent=2, sort_keys=True)
    stream.write("\n")
PY
fi

exit "$result"
