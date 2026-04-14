#!/usr/bin/env bash
set -euo pipefail

SESSION="${1:-}"
if [[ "$SESSION" == "--session" ]]; then
  SESSION="${2:-}"
fi
if [[ -z "$SESSION" ]]; then
  echo "Usage: status.sh --session <name>" >&2
  exit 2
fi

WD_WINDOW="${SESSION}-controller-watchdog"
SESSION_SLUG="$(printf '%s' "$SESSION" | sed -E 's/[^a-zA-Z0-9._-]+/-/g')"
LOG="/tmp/${SESSION_SLUG}-watchdog-controller-proxy.log"

echo "watchdog_window: ${SESSION}:${WD_WINDOW}"
if tmux has-session -t "$SESSION" 2>/dev/null \
  && tmux list-windows -t "$SESSION" -F '#{window_name}' | rg -qx "$WD_WINDOW"; then
  echo "running: yes"
  echo "window_index: $(tmux list-windows -t "$SESSION" -F '#{window_name}:#{window_index}' | rg "^${WD_WINDOW}:" | cut -d: -f2)"
  echo "pane_output_tail:"
  tmux capture-pane -t "${SESSION}:${WD_WINDOW}" -p | tail -n 20
else
  echo "running: no"
fi

echo "log_file: $LOG"
if [[ -f "$LOG" ]]; then
  tail -n 25 "$LOG"
else
  echo "(no log yet)"
fi

echo "open_quality_loop_beads:"
if command -v br >/dev/null 2>&1; then
  br list --status=open 2>/dev/null | sed -E 's/\x1b\[[0-9;]*m//g' | rg 'Quality loops for bd-' || echo "(none)"
else
  echo "(br not found in PATH)"
fi
