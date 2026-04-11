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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${SCRIPT_DIR}/watchdog_controller_proxy.sh"
SESSION_SLUG="$(printf '%s' "$SESSION" | sed -E 's/[^a-zA-Z0-9._-]+/-/g')"
LOG_FILE="/tmp/${SESSION_SLUG}-watchdog-controller-proxy.log"
WATCHDOG_CMD=""
SHELL_BIN="${SHELL:-/bin/bash}"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "session not found: $SESSION" >&2
  exit 1
fi

# Run the watchdog in its own session so robot-send pane indices remain unique
# within the controlled session.
tmux has-session -t "$WD_SESSION" 2>/dev/null && tmux kill-session -t "$WD_SESSION" || true

printf -v WATCHDOG_CMD \
  'exec %q --session %q --project-dir %q --controller-title-regex %q --epic %q --beads %q --interval-seconds %q --exit-mode %q' \
  "$SCRIPT" \
  "$SESSION" \
  "$PROJECT_DIR" \
  "$CONTROLLER_TITLE_REGEX" \
  "$EPIC" \
  "$BEADS" \
  "$INTERVAL_SECONDS" \
  "$EXIT_MODE"

printf -v WATCHDOG_CMD 'exec %q -lc %q' "$SHELL_BIN" "$WATCHDOG_CMD"

tmux new-session -d -s "$WD_SESSION" -n "$WD_WINDOW" "$WATCHDOG_CMD"

echo "started watchdog session ${WD_SESSION}:${WD_WINDOW}"
echo "controlled_session: ${SESSION}"
echo "log: $LOG_FILE"
