#!/usr/bin/env bash
set -euo pipefail

SESSION=""
PROJECT_DIR=""
CONTROLLER_TITLE_REGEX=""
EPIC=""
BEADS=""
INTERVAL_SECONDS=420
EXIT_MODE="confirm"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION="$2"; shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --controller-title-regex) CONTROLLER_TITLE_REGEX="$2"; shift 2 ;;
    --epic) EPIC="$2"; shift 2 ;;
    --beads) BEADS="$2"; shift 2 ;;
    --interval-seconds) INTERVAL_SECONDS="$2"; shift 2 ;;
    --exit-mode) EXIT_MODE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$SESSION" || -z "$PROJECT_DIR" || -z "$CONTROLLER_TITLE_REGEX" || -z "$EPIC" || -z "$BEADS" ]]; then
  echo "Missing required args." >&2
  echo "Usage: start.sh --session <name> --project-dir <path> --controller-title-regex <regex> --epic <bd-id> --beads <csv> [--interval-seconds <n>] [--exit-mode auto|confirm]" >&2
  exit 2
fi

WD_SESSION="${SESSION}-controller-proxy-watchdog"
WD_WINDOW="${SESSION}-controller-watchdog"
SCRIPT="$HOME/.agents/skills/controller-proxy-watchdog/watchdog_controller_proxy.sh"
SESSION_SLUG="$(printf '%s' "$SESSION" | sed -E 's/[^a-zA-Z0-9._-]+/-/g')"
LOG_FILE="/tmp/${SESSION_SLUG}-watchdog-controller-proxy.log"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "session not found: $SESSION" >&2
  exit 1
fi

# Remove prior watchdog window in the controlled session if present.
tmux list-windows -t "$SESSION" -F '#{window_name}' | rg -qx "$WD_WINDOW" \
  && tmux kill-window -t "${SESSION}:${WD_WINDOW}" || true

tmux new-window -t "$SESSION" -n "$WD_WINDOW" \
  "$SCRIPT --session '$SESSION' --project-dir '$PROJECT_DIR' --controller-title-regex '$CONTROLLER_TITLE_REGEX' --epic '$EPIC' --beads '$BEADS' --interval-seconds '$INTERVAL_SECONDS' --exit-mode '$EXIT_MODE'"

echo "started ${SESSION}:${WD_WINDOW}"
echo "log: $LOG_FILE"
