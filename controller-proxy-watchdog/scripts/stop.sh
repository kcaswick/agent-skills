#!/usr/bin/env bash
set -euo pipefail

SESSION="${1:-}"
if [[ "$SESSION" == "--session" ]]; then
  SESSION="${2:-}"
fi
if [[ -z "$SESSION" ]]; then
  echo "Usage: stop.sh --session <name>" >&2
  exit 2
fi

WD_WINDOW="${SESSION}-controller-watchdog"
if tmux has-session -t "$SESSION" 2>/dev/null \
  && tmux list-windows -t "$SESSION" -F '#{window_name}' | rg -qx "$WD_WINDOW"; then
  tmux kill-window -t "${SESSION}:${WD_WINDOW}"
  echo "stopped ${SESSION}:${WD_WINDOW}"
else
  echo "not running: ${SESSION}:${WD_WINDOW}"
fi
