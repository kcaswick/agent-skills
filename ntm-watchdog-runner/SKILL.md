---
name: ntm-watchdog-runner
description: Execute the coordination-watchdog-pattern in environments without a native scheduler. Runs a bash loop that periodically notifies a controller pane. Uses ntm, tmux, and br. Use this skill when your harness does not provide ScheduleWakeup or CronCreate.
allowed-tools: "Bash(ntm *), Bash(br *), Bash(tmux *), Bash(rg *), Read, Grep, Glob"
---

# NTM Watchdog Runner

Executes `coordination-watchdog-pattern` in environments without a native
harness scheduler. Runs a bash watchdog loop inside a dedicated tmux window
that sends periodic coordination prompts to a controller pane using
`ntm --robot-send`.

If your harness provides `ScheduleWakeup` or `CronCreate`, use those instead
and skip this skill — `coordination-watchdog-pattern` describes what to send
on each tick.

## Files

- `scripts/watchdog_controller_proxy.sh` — core watchdog loop
- `scripts/start.sh` — start watchdog in a dedicated window inside the controlled session
- `scripts/stop.sh` — stop watchdog window
- `scripts/status.sh` — show watchdog window state, recent pane output, and logs

## Start

```bash
~/.agents/skills/ntm-watchdog-runner/scripts/start.sh \
  --session project-session \
  --project-dir /abs/path/to/project \
  --controller-title-regex 'controller.*claude|controller.*codex|controller.*proxy' \
  --epic bd-epic \
  --beads bd-a,bd-b,bd-c \
  --interval-seconds 420 \
  --exit-mode confirm
```

Options:
- `--interval-seconds` (default: 420) — cadence between watchdog ticks
- `--exit-mode confirm|auto` — `confirm` (default): sends recurring action-required
  notice on each closed-epic tick, with a 10-tick safety limit before exit;
  `auto`: exits immediately when the epic is closed

## Status

```bash
~/.agents/skills/ntm-watchdog-runner/scripts/status.sh --session project-session
```

## Stop

```bash
~/.agents/skills/ntm-watchdog-runner/scripts/stop.sh --session project-session
```

## Dependency Skills

| Skill | Role |
|---|---|
| **coordination-watchdog-pattern** | Defines the tick cadence, state machine, and prompt semantics this runner executes |
| **ntm** | Pane orchestration: robot-send, pane ID discovery |
