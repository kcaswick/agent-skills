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

WD_SESSION="${SESSION}-controller-proxy-watchdog"
if tmux has-session -t "$WD_SESSION" 2>/dev/null; then
  tmux kill-session -t "$WD_SESSION"
  echo "stopped ${WD_SESSION}"
else
  echo "not running: ${WD_SESSION}"
fi
