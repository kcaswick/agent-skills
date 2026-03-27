#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
watchdog_controller_proxy.sh

Notify a controller-proxy pane on a cadence with actionable assignment context.
The script does NOT assign work directly. It sends a prompt to a controller pane
selected by pane title regex.

Required:
  --session NAME                 tmux/ntm session (e.g. project-session)
  --project-dir PATH             repo path where `br` commands run
  --controller-title-regex REGEX pane title matcher for controller-proxy pane
  --epic BEAD_ID                 epic bead id to stop on close (e.g. bd-2vx)
  --beads CSV                    managed bead ids (e.g. bd-a,bd-b,bd-c)

Optional:
  --interval-seconds N           check cadence (default: 420)
  --exit-mode MODE               exit behavior: auto|confirm (default: confirm)
  --log-file PATH                watchdog log path
  --once                         run one iteration and exit
  --dry-run                      print prompt/log only, do not send
  --help                         show this help

Example:
  scripts/watchdog_controller_proxy.sh \
    --session project-session \
    --project-dir /abs/path/to/project \
    --controller-title-regex 'controller.*codex|controller.*proxy' \
    --epic bd-epic \
    --beads bd-a,bd-b,bd-c \
    --interval-seconds 420
EOF
}

SESSION=""
PROJECT_DIR=""
CONTROLLER_TITLE_REGEX=""
EPIC=""
BEADS_CSV=""
INTERVAL_SECONDS=420
EXIT_MODE="confirm"
DEFAULT_LOG_FILE="/tmp/controller-watchdog-controller-proxy.log"
LOG_FILE="$DEFAULT_LOG_FILE"
LOG_FILE_EXPLICIT=0
ONCE=0
DRY_RUN=0

EXIT_REASON="startup"

write_log_line() {
  local target="$1"
  local message="$2"
  local target_dir
  target_dir="$(dirname "$target")"
  mkdir -p "$target_dir" 2>/dev/null || return 1
  printf '%s\n' "$message" >> "$target" 2>/dev/null || return 1
}

log() {
  local line="$1"
  local message
  message="[controller-watchdog] $(date -Is) $line"
  printf '%s\n' "$message" >&2 || true
  if ! write_log_line "$LOG_FILE" "$message"; then
    if [[ "$LOG_FILE" != "$DEFAULT_LOG_FILE" ]]; then
      write_log_line "$DEFAULT_LOG_FILE" "$message" || true
    fi
  fi
}

log_exit() {
  local code="$1"
  log "exit code=$code reason=$EXIT_REASON"
}

trap 'log_exit $?' EXIT
trap 'EXIT_REASON="received SIGINT"; exit 130' INT
trap 'EXIT_REASON="received SIGTERM"; exit 143' TERM

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION="$2"; shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --controller-title-regex) CONTROLLER_TITLE_REGEX="$2"; shift 2 ;;
    --epic) EPIC="$2"; shift 2 ;;
    --beads) BEADS_CSV="$2"; shift 2 ;;
    --interval-seconds) INTERVAL_SECONDS="$2"; shift 2 ;;
    --exit-mode) EXIT_MODE="$2"; shift 2 ;;
    --log-file) LOG_FILE="$2"; LOG_FILE_EXPLICIT=1; shift 2 ;;
    --once) ONCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h)
      EXIT_REASON="help requested"
      usage
      exit 0
      ;;
    *)
      EXIT_REASON="unknown arg: $1"
      echo "Unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
done

strip_ansi() {
  sed -E 's/\x1b\[[0-9;]*m//g'
}

if [[ -z "$SESSION" || -z "$PROJECT_DIR" || -z "$CONTROLLER_TITLE_REGEX" || -z "$EPIC" || -z "$BEADS_CSV" ]]; then
  EXIT_REASON="missing required args"
  echo "Missing required args." >&2
  usage
  exit 2
fi

if ! [[ "$INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || [[ "$INTERVAL_SECONDS" -lt 60 ]]; then
  EXIT_REASON="invalid interval-seconds: $INTERVAL_SECONDS"
  echo "--interval-seconds must be an integer >= 60" >&2
  exit 2
fi
if [[ "$EXIT_MODE" != "auto" && "$EXIT_MODE" != "confirm" ]]; then
  EXIT_REASON="invalid exit-mode: $EXIT_MODE"
  echo "--exit-mode must be one of: auto, confirm" >&2
  exit 2
fi

IFS=',' read -r -a BEADS <<<"$BEADS_CSV"
SESSION_SLUG="$(printf '%s' "$SESSION" | sed -E 's/[^a-zA-Z0-9._-]+/-/g')"

if [[ "$LOG_FILE_EXPLICIT" -eq 0 ]]; then
  LOG_FILE="/tmp/${SESSION_SLUG}-watchdog-controller-proxy.log"
fi

if ! mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
  EXIT_REASON="unable to create log directory for $LOG_FILE"
  echo "Unable to create log directory for $LOG_FILE" >&2
  exit 1
fi
if ! : >>"$LOG_FILE" 2>/dev/null; then
  EXIT_REASON="unable to write log file $LOG_FILE"
  echo "Unable to write log file $LOG_FILE" >&2
  exit 1
fi

status_of_bead() {
  local bead="$1"
  (
    cd "$PROJECT_DIR"
    br show "$bead" 2>/dev/null | strip_ansi | rg -o 'CLOSED|OPEN|IN_PROGRESS' | head -n1
  )
}

ready_beads_csv() {
  (
    cd "$PROJECT_DIR"
    br ready 2>/dev/null \
      | strip_ansi \
      | rg '^[0-9]+\.' \
      | sed -E 's/^[0-9]+\. \[[^]]+\] \[[^]]+\] (bd-[a-z0-9]+):.*/\1/' \
      | paste -sd, - || true
  )
}

find_controller_pane_index() {
  local match
  match="$(tmux list-panes -t "$SESSION" -F '#{pane_index}|#{pane_title}' \
    | rg -i "$CONTROLLER_TITLE_REGEX" \
    | head -n1 \
    | cut -d'|' -f1 || true)"
  if [[ -n "$match" ]]; then
    printf '%s\n' "$match"
    return 0
  fi
  # Fallback: first pane in session to avoid silent watchdog stalls when titles change.
  tmux list-panes -t "$SESSION" -F '#{pane_index}' | head -n1
}

open_quality_loop_beads_csv() {
  (
    cd "$PROJECT_DIR"
    br list --status=open 2>/dev/null \
      | strip_ansi \
      | rg 'Quality loops for bd-' \
      | sed -E 's/^.[[:space:]]+(bd-[a-z0-9]+).*/\1/' \
      | paste -sd, - || true
  )
}

validate_robot_send_output() {
  local pane_index="$1"
  local output="$2"
  python3 -c '
import json
import sys

requested_pane = str(sys.argv[1])
raw = sys.stdin.read()

try:
    payload = json.loads(raw)
except json.JSONDecodeError as exc:
    print(f"robot-send output was not valid JSON: {exc}", file=sys.stderr)
    sys.exit(2)

if payload.get("success") is not True:
    print("robot-send reported success=false", file=sys.stderr)
    sys.exit(3)

failed = [str(item) for item in (payload.get("failed") or [])]
successful = [str(item) for item in (payload.get("successful") or [])]

if failed:
    print(f"robot-send reported failed targets: {failed}", file=sys.stderr)
    sys.exit(4)

if requested_pane not in successful:
    print(
        f"requested pane {requested_pane} missing from successful targets: {successful}",
        file=sys.stderr,
    )
    sys.exit(5)
' "$pane_index" <<<"$output"
}

send_prompt_to_controller() {
  local pane_index="$1"
  local prompt="$2"
  local output=""
  local robot_send_status=0
  local restore_errexit=0
  local restore_xtrace=0
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "dry-run target_pane=${pane_index} prompt=$(printf '%q' "$prompt")"
    return 0
  fi
  case "$-" in
    *e*)
      restore_errexit=1
      set +e
      ;;
  esac
  case "$-" in
    *x*)
      restore_xtrace=1
      set +x
      ;;
  esac
  output="$(ntm --robot-send="$SESSION" --panes="$pane_index" --msg="$prompt" --enter --json 2>&1)"
  robot_send_status=$?
  if [[ "$restore_xtrace" -eq 1 ]]; then
    set -x
  fi
  if [[ "$restore_errexit" -eq 1 ]]; then
    set -e
  fi
  if [[ "$robot_send_status" -ne 0 ]]; then
    EXIT_REASON="robot-send command failed pane_index=$pane_index"
    log "robot-send-command-failed pane_index=$pane_index output=$(printf '%q' "$output")"
    return 1
  fi
  if ! validate_robot_send_output "$pane_index" "$output"; then
    EXIT_REASON="robot-send validation failed pane_index=$pane_index"
    log "robot-send-validation-failed pane_index=$pane_index output=$(printf '%q' "$output")"
    return 1
  fi
}

build_prompt() {
  local ready="$1"
  local in_progress="$2"
  local quality_due="$3"
  cat <<EOF
<<<WATCHDOG TICK>>>
Watchdog tick for session '$SESSION'.
Use pane captures as source of truth (not ntm status/health), then coordinate assignments.

State:
- ready_beads: ${ready}
- in_progress_beads: ${in_progress}
- quality_loops_due: ${quality_due}

Actions:
1. Verify active worker state with pane captures and br show.
2. Assign ready implementation beads by dependency order and conflict safety, and require Agent Mail report + '[CHECK MAIL] ...' handoff ping for each assignment.
3. For workers blocked by deps/conflicts, assign targeted review tasks.
4. Run post-bead quality loops for each bead in quality_loops_due:
   - self-review
   - cross-review
   - random exploration
5. For each loop/review assignment, require Agent Mail findings plus '[CHECK MAIL] ...' ping; use pane pings as notification only, and fetch inbox content as source of truth before closure.
6. Track completion in beads by closing each quality-loop bead with findings summary.
7. Report assignments and completion handoffs.
<<<END WATCHDOG TICK>>>
EOF
}

build_close_confirm_prompt() {
  local ready="$1"
  local in_progress="$2"
  local quality_due="$3"
  cat <<EOF
<<<WATCHDOG EPIC CLOSED>>>
Watchdog action required for session '$SESSION':
Epic '$EPIC' is CLOSED, but controller verification is still required before the watchdog can be stopped.

State:
- ready_beads: ${ready}
- in_progress_beads: ${in_progress}
- quality_loops_due: ${quality_due}

Actions:
1. Verify active worker state with pane captures and br show.
2. Verify there are no follow-up/open beads that still require coordination
   (for example: newly created follow-up tasks, docs polish, or remaining quality-loop beads).
3. If work remains, coordinate it now and leave the watchdog running.
4. Only if completion is truly done, stop watchdog explicitly:
   ~/.agents/skills/controller-proxy-watchdog/stop.sh --session $SESSION

This is not FYI. Controller action is required on every closed-epic tick until the watchdog is stopped.
<<<END WATCHDOG EPIC CLOSED>>>
EOF
}

log "start session=$SESSION epic=$EPIC interval=${INTERVAL_SECONDS}s beads=$BEADS_CSV"

while true; do
  epic_status="$(status_of_bead "$EPIC")"
  ready_csv="$(ready_beads_csv)"
  [[ -n "${ready_csv:-}" ]] || ready_csv="none"

  in_progress=()
  for bead in "${BEADS[@]}"; do
    st="$(status_of_bead "$bead")"
    case "$st" in
      IN_PROGRESS) in_progress+=("$bead") ;;
    esac
  done

  in_progress_csv="none"
  if [[ "${#in_progress[@]}" -gt 0 ]]; then
    in_progress_csv="$(printf '%s\n' "${in_progress[@]}" | paste -sd, -)"
  fi

  quality_due_csv="$(open_quality_loop_beads_csv)"
  [[ -n "${quality_due_csv:-}" ]] || quality_due_csv="none"

  log "tick epic=$epic_status ready=$ready_csv in_progress=$in_progress_csv quality_due=$quality_due_csv"

  controller_pane_index="$(find_controller_pane_index || true)"
  if [[ -z "${controller_pane_index:-}" ]]; then
    log "no-controller-pane regex=$CONTROLLER_TITLE_REGEX"
  else
    if [[ "$epic_status" == "CLOSED" ]]; then
      if [[ "$EXIT_MODE" == "auto" ]]; then
        EXIT_REASON="epic closed with exit-mode=auto"
        log "epic-closed exiting epic=$EPIC mode=auto"
        exit 0
      fi
      close_prompt="$(build_close_confirm_prompt "$ready_csv" "$in_progress_csv" "$quality_due_csv")"
      send_prompt_to_controller "$controller_pane_index" "$close_prompt"
      log "epic-closed notify-sent pane_index=$controller_pane_index mode=confirm"
    else
      prompt="$(build_prompt "$ready_csv" "$in_progress_csv" "$quality_due_csv")"
      send_prompt_to_controller "$controller_pane_index" "$prompt"
      log "prompt-sent pane_index=$controller_pane_index"
    fi
  fi

  if [[ "$ONCE" -eq 1 ]]; then
    EXIT_REASON="once-mode complete"
    log "once-mode exiting"
    exit 0
  fi

  EXIT_REASON="sleeping ${INTERVAL_SECONDS}s before next tick"
  sleep "$INTERVAL_SECONDS"
done
