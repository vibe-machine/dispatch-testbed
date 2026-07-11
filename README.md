# Dispatch Testbed

A deliberately tiny target repository for VibeMachine dispatch rehearsals. It provides a real Swift build, a seeded Beads task, and a deterministic fake-agent wave without OneWorkspace’s build weight.

## First run

```bash
git clone https://github.com/vibe-machine/dispatch-testbed.git
cd dispatch-testbed
mise trust
mise run setup
```

Setup installs a project-specific launchd Dolt server on port 3317, imports the seeded `dtb-1` bead using the embedded-init workaround required by bd 1.0.5, and runs the package tests. The server is independent from OneWorkspace’s port 3307 server.

## Test tiers

The local fake-agent lifecycle is deterministic and should finish in under two minutes:

```bash
mise run wave:dispatch dtb-1 --agent fake
```

It claims the bead, provisions a Git worktree, applies the seeded one-file implementation and test, qualifies it with `mise run test`, fast-forwards `main`, and closes the bead.

For a rehearsal wave, select this repository in OneApp’s VibeMachine Plan view, choose `dtb-1`, enable rehearsal, and dispatch. Inspect the generated contract and materialized runtime without starting a real worker.

For a real Codex run, leave `dtb-1` open in a fresh clone, select Codex and one worker in VibeMachine, and dispatch it against `main`. The worker contract uses only:

```bash
mise run build
mise run test
```

When `AGENT_RUNTIME_HOME` or `CODEX_HOME` is present, the test task writes `test-evidence.json` there for the runtime Stop gate.
