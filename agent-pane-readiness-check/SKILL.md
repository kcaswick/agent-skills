---
name: agent-pane-readiness-check
description: Pre-send readiness check for a target tmux pane. Verify the pane is at an active agent prompt before sending any automated message, and recover it if not. Use before any ntm --robot-send or tmux send-keys targeting a specific pane.
---

# Agent Pane Readiness Check

Before sending any targeted assignment to a pane, perform this readiness check.
Do **not** send blindly by pane index.

Operational rule: never interpret "only one visible pane in the current window"
as "the session only has one pane." Before adding or reassigning workers, inspect
**all** tmux windows/panes in the session.

## Steps

1. Check pane command/title state:
```bash
tmux list-panes -t <session> -F '#{pane_index}|#{pane_title}|#{pane_current_command}'
```

2. Check recent pane output:
```bash
tmux capture-pane -t <session>:<window>.<pane> -p | tail -n 40
```

3. **Never send recovery keystrokes to the user's active pane.** Check first:
```bash
tmux list-panes -t <session> -F '#{pane_index}|#{pane_active}|#{window_active}'
```
If `pane_active=1` and `window_active=1`, the user is working in that pane.
Skip recovery and route work elsewhere.

4. Recover based on observed state:
   - **Agent hanging with unsubmitted input** (prompt visible, cursor at end of
     a message that was never submitted — common when a trailing newline was
     absorbed into the message body):
     ```bash
     tmux send-keys -t <session>:<window>.<pane> Enter
     ```
   - **Pane in shell mode** (`sh`, `bash`, `zsh`, etc.) or **suspended process**:
     ```bash
     tmux send-keys -t <session>:<window>.<pane> C-c Enter
     tmux send-keys -t <session>:<window>.<pane> 'fg' Enter
     ```
   - If still not agent-ready, restart/recover the pane before assignment.

5. Only send assignment after the pane shows active agent prompt context.

## Rule

If a pane is not confirmed ready, recover it first or route the work to another
ready pane. Never send to an unverified pane.

## Capability Reference

- **Pane orchestration** — default adapter: `ntm`
  (for pane ID discovery and the `--robot-send` command that follows this check)
