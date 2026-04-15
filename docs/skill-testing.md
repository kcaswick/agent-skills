# Skill Testing Policy

This document defines the default testing approach for skills in this repo,
especially skills that drive NTM, tmux panes, Agent Mail, Beads, or other
multi-agent coordination tools.

## Core Rule

Never perform live tests against already existing sessions.

Existing tmux/NTM sessions may contain the user's active shell, controller panes,
production agents, in-progress assignments, or state that other agents depend
on. Treat them as read-only observation targets unless the user explicitly
authorizes a specific live-session action.

Do not send these to existing sessions:

- prompts or watchdog ticks
- `ntm send` or `ntm --robot-send`
- Enter/recovery keystrokes
- interrupts, restarts, respawns, or cleanup commands
- controller or worker assignment prompts
- Agent Mail handoff prompts intended to trigger real work

Read-only inspection is allowed when needed, for example `tmux list-panes`,
`ntm status --json`, `ntm --robot-status`, pane captures, and dry-run commands
that do not mutate session state.

## Required Live-Test Pattern

When live behavior must be tested, create disposable sessions yourself.

Use names that are obviously temporary and unique, for example:

```bash
session="test-controller-proxy-watchdog-$(date +%Y%m%d-%H%M%S)"
```

The test session should be the smallest topology that exercises the behavior:

- one disposable session
- one controller or worker pane unless more are strictly required
- one test window for watchdog/session-bound behavior
- short, explicit prompts that request no real work
- short-lived intervals and `--once` where supported

Clean up only the disposable sessions, windows, panes, or files you created.
Do not clean or alter unrelated sessions.

## Cost Control

Agent processes are expensive and can trigger long replies. Minimize cost before
spawning anything:

1. Prefer `--dry-run`, `bash -n`, `shellcheck`, unit-level shell tests, and
   CLI JSON inspection.
2. If a CLI supports preview mode, use that before any actual send or spawn.
3. If an agent must be spawned, use the cheapest available model/profile for
   each provider in the current environment.
4. Spawn one agent at a time unless the test specifically requires interaction
   across multiple providers.
5. Use minimal prompts such as:

```text
<<<TEST>>>
No real work is required. Reply with exactly: received
<<<END TEST>>>
```

Avoid prompts that invite investigation, code changes, or multi-step reasoning.

## Controller-Proxy Watchdog Example

For `controller-proxy-watchdog`, test in layers:

1. Run syntax and lint checks:

```bash
bash -n controller-proxy-watchdog/scripts/*.sh
shellcheck controller-proxy-watchdog/scripts/*.sh
```

2. Test discovery and payload construction with `--once --dry-run`.

3. If real delivery must be tested, create a disposable NTM session and target
   only panes in that session. Do not use an existing project controller.

4. Use tiny test data and prompts. Confirm delivery with pane capture, then
   stop the disposable watchdog and kill only the disposable session.

5. Report any limitations clearly, such as unavailable local Beads state or an
   Agent Mail server restart requirement.

## Reporting

When reporting test results, include:

- whether any live agent was spawned
- the disposable session name, if applicable
- which commands were dry-run versus live
- what was verified by direct output or pane capture
- any skipped test and the concrete reason

