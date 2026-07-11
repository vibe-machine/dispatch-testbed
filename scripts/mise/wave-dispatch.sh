#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BEAD_ID="${1:-}"
AGENT=""
shift $(( $# > 0 ? 1 : 0 ))
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

[ -n "$BEAD_ID" ] || { echo "usage: mise run wave:dispatch <bead> --agent fake" >&2; exit 64; }
[ "$AGENT" = "fake" ] || {
  echo "This local harness implements --agent fake. Use OneWorkspace/VibeMachine for a real Codex dispatch." >&2
  exit 64
}
[ "$BEAD_ID" = "dtb-1" ] || { echo "fake agent only knows seeded bead dtb-1" >&2; exit 65; }

lane="$ROOT/.lanes/$BEAD_ID"
branch="wave/$BEAD_ID"
cleanup() {
  git -C "$ROOT" worktree remove --force "$lane" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "phase=dispatching bead=$BEAD_ID agent=fake"
bd -C "$ROOT" update "$BEAD_ID" --claim
mkdir -p "$ROOT/.lanes"
git -C "$ROOT" branch -D "$branch" >/dev/null 2>&1 || true
git -C "$ROOT" worktree add -q -b "$branch" "$lane" main

echo "phase=implementing lane=$lane"
cp "$ROOT/fixtures/seed-add-clamp/Sources/DispatchTestbed/Arithmetic.swift" "$lane/Sources/DispatchTestbed/Arithmetic.swift"
cp "$ROOT/fixtures/seed-add-clamp/Tests/DispatchTestbedTests/ArithmeticTests.swift" "$lane/Tests/DispatchTestbedTests/ArithmeticTests.swift"
mise -C "$lane" run test
git -C "$lane" add Sources Tests
git -C "$lane" commit -q -m "feat: add clamp operation"

echo "phase=qualifying"
mise -C "$lane" run test
echo "phase=merging"
git -C "$ROOT" merge --ff-only "$branch"
bd -C "$ROOT" close "$BEAD_ID" --reason "Fake-agent wave completed and merged."
cleanup
git -C "$ROOT" branch -d "$branch" >/dev/null
trap - EXIT
echo "phase=merge-complete bead=$BEAD_ID"
