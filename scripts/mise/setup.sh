#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mise trust "$ROOT/mise.toml"
"$ROOT/scripts/beads-dolt-launchd.sh" --port 3317
mise run test
