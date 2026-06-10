---
name: agent-pane-readiness-check
description: Pre-send readiness check for a target tmux pane. Verify the pane is at an active agent prompt before sending any automated message, and recover it if not. Use before any ntm --robot-send or tmux send-keys targeting a specific pane.
allowed-tools: "Bash(ntm *), Bash(tmux *)"
---

# Agent Pane Readiness Check

Before sending any targeted assignment to a pane, perform this readiness check.
Do **not** send blindly by pane index.

Operational rule: never interpret "only one visible pane in the current window"
as "the session only has one pane." Before adding or reassigning workers, inspect
**all** tmux windows/panes in the session.

## Steps

1. Check pane states across all agent panes:
```bash
ntm --robot-activity=<session> --json
```
Look for `"state": "WAITING"` on the target pane — that means it is at an active
agent prompt and ready for assignment. GENERATING, THINKING, ERROR, and STALLED
require further inspection or recovery before sending.

2. Inspect the specific pane's recent output:
```bash
ntm --robot-inspect-pane=<session> --index=<pane-index> --json
```
Check `agent.state` and `output.last_lines` to confirm the pane is at a clean
prompt. A WAITING pane with recent agent output is unambiguously ready.

3. **Never send recovery keystrokes to the user's active pane.** `ntm
--robot-activity` lists only agent panes by default — a pane absent from that
output may be user-owned. For an explicit check:
```bash
tmux list-panes -s -t <session> -F '#{pane_id}|#{pane_active}|#{window_active}'
```
If a pane shows `pane_active=1` and `window_active=1`, the user is working in
that pane. Skip recovery and route work elsewhere.

4. Recover based on observed state (always target by pane ID, never index):
   - **ERROR or STALLED — interrupt the process:**
     ```bash
     ntm --robot-interrupt=<session> --panes=<pane-id>
     ```
   - **Agent hanging with unsubmitted input** (prompt visible, cursor at end of
     a message that was never submitted — no ntm equivalent for a bare Enter):
     ```bash
     tmux send-keys -t <pane-id> Enter
     ```
   - **Pane in shell mode** (`sh`, `bash`, `zsh`) or **suspended process** —
     interrupt then foreground:
     ```bash
     ntm --robot-interrupt=<session> --panes=<pane-id>
     tmux send-keys -t <pane-id> 'fg' Enter
     ```
   - **Pane unrecoverable** — restart it:
     ```bash
     ntm --robot-restart-pane=<session> --panes=<pane-id>
     ```

5. Only send assignment after the pane shows `"state": "WAITING"` in ntm
activity output.

## Rule

If a pane is not confirmed ready, recover it first or route the work to another
ready pane. Never send to an unverified pane.

## Fallback: Using tmux directly

When ntm is unavailable, use raw tmux equivalents:

```bash
# Step 1 equivalent — list pane states across all windows
tmux list-panes -s -t <session> -F '#{pane_id}|#{pane_title}|#{pane_current_command}'

# Step 2 equivalent — inspect recent pane output
tmux capture-pane -t <pane-id> -p | tail -n 40

# Step 4 recovery equivalents
tmux send-keys -t <pane-id> C-c Enter      # interrupt
tmux send-keys -t <pane-id> Enter           # submit hanging input
tmux send-keys -t <pane-id> 'fg' Enter     # foreground suspended process
```

## Capability Reference

- **Pane orchestration** — default adapter: `ntm`
  (for pane ID discovery and the `--robot-send` command that follows this check)
