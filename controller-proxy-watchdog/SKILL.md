---
name: controller-proxy-watchdog
description: "Session-aware watchdog that notifies a controller-proxy pane (by title regex) to coordinate bead assignments and quality loops. Uses ntm robot-send, not direct auto-assignment."
allowed-tools: "Bash(ntm *), Bash(br *), Bash(tmux *), Bash(rg *), Read, Grep, Glob"
---

# Controller Proxy Watchdog

This skill runs a background watchdog that periodically sends a coordination prompt
into a controller-proxy pane. It does not assign beads directly.

## Files

- `scripts/watchdog_controller_proxy.sh`: core watchdog loop
- `scripts/start.sh`: start watchdog in a dedicated window inside the controlled tmux session
- `scripts/stop.sh`: stop watchdog window
- `scripts/status.sh`: show watchdog window state, recent pane output, and logs

## Dependency Skills

| Skill | Role in this workflow |
|---|---|
| **agent-swarm-workflow** | Defines self-review, cross-review, and random-exploration loop structure that the watchdog prompts the controller to execute |
| **beads-workflow** | Provides bead create/update/close lifecycle so quality-loop work is tracked as beads, not ad-hoc notes |

## Properties

- Uses `br` for readiness/progress state.
- Selects controller pane by title regex (not pane number).
- Runs as a watchdog window inside the controlled tmux session.
- Discovers the controller with `tmux list-panes -a` and captures its tmux pane id
  (`%27`, `%31`, ...), which is globally unique within the session.
- Sends messages with `ntm --robot-send ... --panes=<pane_id> --json`.
- Treats partial or failed robot-send results as errors.
- Uses Agent Mail + explicit `ntm --robot-send ...` handoff commands for `<<<CHECK MAIL>>> ... <<<END CHECK MAIL>>>` assignment-completion pings.
- Requires pane-readiness verification before targeted worker sends.
- Uses session-derived log file by default:
  - `/tmp/<session>-watchdog-controller-proxy.log`
- Writes output to both the watchdog pane and the log file.
- Tracks quality loops via companion beads (e.g. `Quality loops for bd-...`),
  not tmp ledgers. Tracking explicitly includes creating the companion bead
  whenever/wherever a quality loop is needed and no such bead exists yet.
- Exit behavior is configurable:
  - `confirm` (default): sends a recurring action-required verify-completion notice on each closed-epic tick and waits for manual stop
  - `auto`: exits immediately when the epic is closed

## Required Pre-Send Pane Check

Before sending any targeted assignment to a worker pane (from the controller),
perform this readiness check first. Do **not** send blindly by pane index.

Operational rule: never interpret "only one visible pane in the current
window" as "the session only has one pane." Before adding or reassigning
workers, inspect **all** tmux windows/panes in the session.

1. Check pane command/title state:
```bash
\tmux list-panes -t <session> -F '#{pane_index}|#{pane_title}|#{pane_current_command}'
```
2. Check recent pane output:
```bash
\tmux capture-pane -t <session>:<window>.<pane> -p | tail -n 40
```
3. **Never send recovery keystrokes to the user's active pane.** Check first:
   ```bash
   \tmux list-panes -t <session> -F '#{pane_index}|#{pane_active}|#{window_active}'
   ```
   If `pane_active=1` and `window_active=1`, the user is working in that pane.
   Skip recovery and route work elsewhere.

4. Recover based on observed state:
   - **Agent hanging with unsubmitted input** (prompt visible, cursor at end of
     a message that was never submitted — common when a trailing newline was
     absorbed into the message body):
     ```bash
     \tmux send-keys -t <session>:<window>.<pane> Enter
     ```
   - **Pane in shell mode** (`sh`, `bash`, `zsh`, etc.) or **suspended process**:
     ```bash
     \tmux send-keys -t <session>:<window>.<pane> C-c Enter
     \tmux send-keys -t <session>:<window>.<pane> 'fg' Enter
     ```
   - If still not agent-ready, restart/recover the pane before assignment.
5. Only send assignment after the pane shows active agent prompt context.

Controller rule: if a pane is not confirmed ready, recover it first or route
the work to another ready pane.

## Required Handoff Pattern

For every targeted assignment sent to a worker pane:

- Instruct the worker to send the detailed result via Agent Mail (with a
  bead/topic-specific subject or topic).
- Instruct the worker to ping pane 1 with a short handoff marker, and include
  the exact `ntm --robot-send` command with the real session name and worker pane index
  filled in. Do not assume the worker knows the syntax:
  `ntm --robot-send=<session> --panes=1 --msg="<<<CHECK MAIL>>> paneN <bead-or-task> <short status> <<<END CHECK MAIL>>>"`
- Treat pane pings as notification-only. Source of truth is the Agent Mail body
  content, which the controller must fetch before marking work complete.

## Start

```bash
~/.agents/skills/controller-proxy-watchdog/scripts/start.sh \
  --session project-session \
  --project-dir /abs/path/to/project \
  --controller-title-regex 'controller.*claude|controller.*codex|controller.*proxy' \
  --epic bd-epic \
  --beads bd-a,bd-b,bd-c \
  --interval-seconds 420 \
  --exit-mode confirm
```

## Status

```bash
~/.agents/skills/controller-proxy-watchdog/scripts/status.sh --session project-session
```

## Stop

```bash
~/.agents/skills/controller-proxy-watchdog/scripts/stop.sh --session project-session
```

## Quality Loop Tracking

Quality loops are treated as regular beads.

Controller requirements:
- For each implementation bead that needs post-bead loops, ensure there is an
  **open** companion bead named `Quality loops for bd-...`.
- If no open companion bead exists, create one before assigning/running loop
  work.
- A previously closed `Quality loops for bd-...` bead does **not** satisfy this
  requirement for a reopened implementation bead; create a new open companion
  bead for the new loop cycle.
- Run all required loops (`self-review`, `cross-review`, `random exploration`)
  and record findings.
- Close each `Quality loops for bd-...` bead only after findings are recorded
  (or explicitly recorded as no findings).
- For loop assignments, require Agent Mail findings plus an explicit
  `ntm --robot-send=<session> --panes=1 --msg="<<<CHECK MAIL>>> paneN <bead-or-task> <short status> <<<END CHECK MAIL>>>"`
  instruction for each worker before closure.
