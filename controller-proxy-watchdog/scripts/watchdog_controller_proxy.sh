#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
      | sed -E 's/^[0-9]+\. \[[^]]+\] \[[^]]+\] (bd-[a-z0-9.]+):.*/\1/' \
      | paste -sd, - || true
  )
}

find_controller_pane() {
  local matches match_count pane_id pane_ref pane_index pane_title pane_command
  matches="$(
    tmux list-panes -a \
      -F '#{session_name}|#{pane_id}|#{window_index}.#{pane_index}|#{pane_title}|#{pane_current_command}' \
      | rg "^${SESSION}\\|" \
      | cut -d'|' -f2- \
      | rg -i "$CONTROLLER_TITLE_REGEX" || true
  )"
  match_count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [[ "$match_count" -eq 0 ]]; then
    log "no-controller-pane regex=$CONTROLLER_TITLE_REGEX"
    return 1
  fi

  if [[ "$match_count" -ne 1 ]]; then
    log "multiple-controller-pane-matches regex=$CONTROLLER_TITLE_REGEX matches=$(printf '%q' "$matches")"
    return 1
  fi

  pane_id="$(printf '%s\n' "$matches" | cut -d'|' -f1)"
  pane_ref="$(printf '%s\n' "$matches" | cut -d'|' -f2)"
  pane_title="$(printf '%s\n' "$matches" | cut -d'|' -f3)"
  pane_command="$(printf '%s\n' "$matches" | cut -d'|' -f4)"
  pane_index="${pane_ref##*.}"

  log "controller-pane pane_id=$pane_id pane_ref=$pane_ref pane_index=$pane_index pane_title=$(printf '%q' "$pane_title") pane_command=$(printf '%q' "$pane_command")"
  printf '%s\n' "$pane_id"
  printf '%s\n' "$pane_index"
  printf '%s\n' "$pane_ref"
  printf '%s\n' "$pane_title"
  printf '%s\n' "$pane_command"
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

capture_pane_text() {
  local pane_target="$1"
  tmux capture-pane -t "$pane_target" -p 2>/dev/null | strip_ansi
}

pane_activity_state() {
  local pane_index="$1"
  local output=""
  output="$(ntm --robot-activity="$SESSION" --panes="$pane_index" --json 2>/dev/null || true)"
  python3 -c '
import json
import sys

raw = sys.stdin.read().strip()
if not raw:
    sys.exit(1)

payload = json.loads(raw)
agents = payload.get("agents") or []
if not agents:
    sys.exit(1)

print(agents[0].get("state", ""))
' <<<"$output"
}

wait_for_activity_departure() {
  local pane_index="$1"
  local baseline_state="$2"
  local attempts=8
  local state=""
  local attempt

  for ((attempt = 0; attempt < attempts; attempt++)); do
    state="$(pane_activity_state "$pane_index" || true)"
    if [[ -n "$state" && "$state" != "$baseline_state" && "$state" != "WAITING" ]]; then
      log "controller-activity-changed pane_index=$pane_index from=$baseline_state to=$state"
      return 0
    fi
    sleep 1
  done

  return 1
}

watchdog_prompt_visible() {
  local pane_id="$1"
  local prompt_marker="$2"
  local capture=""

  capture="$(capture_pane_text "$pane_id")"
  if [[ -z "$capture" ]]; then
    return 1
  fi

  printf '%s\n' "$capture" | rg -F -q -- "$prompt_marker"
}

pane_shows_active_response() {
  local pane_id="$1"
  local capture=""

  capture="$(capture_pane_text "$pane_id")"
  if [[ -z "$capture" ]]; then
    return 1
  fi

  printf '%s\n' "$capture" \
    | rg -q 'Working \(|esc to interrupt|^\s*[•◐▶■] |hit your usage limit|rate limit|try again at'
}

controller_blocked_reason() {
  local pane_id="$1"
  local pane_command="$2"
  local capture=""

  case "$pane_command" in
    bash|fish|sh|zsh)
      printf 'controller pane is in shell mode (%s)\n' "$pane_command"
      return 0
      ;;
  esac

  capture="$(capture_pane_text "$pane_id")"
  if [[ -z "$capture" ]]; then
    return 1
  fi

  if printf '%s\n' "$capture" | rg -q 'Do you trust the contents of this directory\?'; then
    printf 'controller is blocked on trust prompt\n'
    return 0
  fi

  if printf '%s\n' "$capture" \
    | rg -q "Update now|Skip until next version|Introducing GPT-5\.4|Try new model|Use existing model|Choose how you'd like Codex to proceed"; then
    printf 'controller is blocked on update prompt\n'
    return 0
  fi

  if printf '%s\n' "$capture" | rg -q 'Press enter to continue'; then
    printf 'controller is blocked on continue prompt\n'
    return 0
  fi

  if printf '%s\n' "$capture" | rg -q 'hit your usage limit|rate limit|try again at'; then
    printf 'controller is blocked on usage limit prompt\n'
    return 0
  fi

  return 1
}

ensure_controller_ready() {
  local pane_id="$1"
  local pane_command="$2"
  local blocked_reason=""

  blocked_reason="$(controller_blocked_reason "$pane_id" "$pane_command" || true)"
  if [[ -n "$blocked_reason" ]]; then
    log "controller-not-ready pane_id=$pane_id reason=$(printf '%q' "$blocked_reason")"
    return 1
  fi

  return 0
}

verify_prompt_consumed() {
  local pane_id="$1"
  local pane_index="$2"
  local baseline_state="$3"
  local prompt_marker="$4"
  local current_state=""
  local attempted_enter=0

  if [[ "$baseline_state" == "WAITING" || -z "$baseline_state" || "$baseline_state" == "UNKNOWN" ]]; then
    if wait_for_activity_departure "$pane_index" "$baseline_state"; then
      return 0
    fi
  else
    current_state="$(pane_activity_state "$pane_index" || true)"
    log "controller-already-busy pane_index=$pane_index baseline=$baseline_state current=${current_state:-unknown}"
  fi

  if watchdog_prompt_visible "$pane_id" "$prompt_marker"; then
    attempted_enter=1
    log "watchdog-draft-detected pane_id=$pane_id pane_index=$pane_index sending-enter"
    tmux send-keys -t "$pane_id" Enter

    current_state="$(pane_activity_state "$pane_index" || true)"
    if [[ "$baseline_state" == "WAITING" || -z "$baseline_state" || "$baseline_state" == "UNKNOWN" ]]; then
      if wait_for_activity_departure "$pane_index" "$baseline_state"; then
        return 0
      fi
    fi
  fi

  if [[ "$attempted_enter" -eq 1 ]] && pane_shows_active_response "$pane_id"; then
    log "controller-active-after-enter pane_id=$pane_id pane_index=$pane_index state_after_enter=${current_state:-unknown}"
    return 0
  fi

  return 1
}

send_prompt_to_controller() {
  local pane_id="$1"
  local pane_index="$2"
  local pane_ref="$3"
  local pane_title="$4"
  local pane_command="$5"
  local prompt="$6"
  local prompt_marker="$7"
  local output=""
  local robot_send_status=0
  local restore_errexit=0
  local restore_xtrace=0
  local baseline_state=""
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "dry-run target_pane=${pane_id} pane_index=${pane_index} pane_ref=${pane_ref} pane_title=$(printf '%q' "$pane_title") prompt=$(printf '%q' "$prompt")"
    return 0
  fi
  if ! ensure_controller_ready "$pane_id" "$pane_command"; then
    EXIT_REASON="controller not ready pane_id=$pane_id"
    return 1
  fi
  baseline_state="$(pane_activity_state "$pane_index" || true)"
  log "controller-activity-before-send pane_id=$pane_id pane_index=$pane_index state=${baseline_state:-unknown}"
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
  output="$(ntm --robot-send="$SESSION" --panes="$pane_id" --msg="$prompt" --json 2>&1)"
  robot_send_status=$?
  if [[ "$restore_xtrace" -eq 1 ]]; then
    set -x
  fi
  if [[ "$restore_errexit" -eq 1 ]]; then
    set -e
  fi
  if [[ "$robot_send_status" -ne 0 ]]; then
    EXIT_REASON="robot-send command failed pane_id=$pane_id"
    log "robot-send-command-failed pane_id=$pane_id output=$(printf '%q' "$output")"
    return 1
  fi
  if ! validate_robot_send_output "$pane_index" "$output"; then
    EXIT_REASON="robot-send validation failed pane_id=$pane_id pane_index=$pane_index"
    log "robot-send-validation-failed pane_id=$pane_id pane_index=$pane_index output=$(printf '%q' "$output")"
    return 1
  fi
  if ! verify_prompt_consumed "$pane_id" "$pane_index" "$baseline_state" "$prompt_marker"; then
    EXIT_REASON="controller did not consume prompt pane_id=$pane_id pane_index=$pane_index"
    log "prompt-not-consumed pane_id=$pane_id pane_index=$pane_index pane_ref=$pane_ref pane_title=$(printf '%q' "$pane_title") marker=$prompt_marker"
    return 1
  fi
}

build_prompt() {
  local ready="$1"
  local in_progress="$2"
  local quality_due="$3"
  local prompt_marker="$4"
  cat <<EOF
<<<WATCHDOG TICK>>>
Watchdog tick for session '$SESSION'.
Use pane captures as source of truth (not ntm status/health), then coordinate assignments.
Watchdog marker: ${prompt_marker}

State:
- ready_beads: ${ready}
- in_progress_beads: ${in_progress}
- quality_loops_due: ${quality_due}

Actions:
1. Verify active worker state with pane captures and br show.
2. Assign ready implementation beads by dependency order and conflict safety. Require an Agent Mail report for each assignment, and tell each worker the exact command to run for the notification ping: ntm --robot-send=$SESSION --panes=1 --msg="<<<CHECK MAIL>>> pane<worker-pane> <bead-or-task> <short status> <<<END CHECK MAIL>>>". Fill in the real worker pane index; do not assume the worker knows the syntax.
3. For workers blocked by deps/conflicts, assign targeted review tasks.
4. Run post-bead quality loops for each bead in quality_loops_due:
   - self-review
   - cross-review
   - random exploration
5. For each loop/review assignment, require Agent Mail findings plus the same exact ntm --robot-send notification command; use pane pings as notification only, and fetch inbox content as source of truth before closure.
6. Track completion in beads by closing each quality-loop bead with findings summary.
7. Report assignments and completion handoffs.
Watchdog marker: ${prompt_marker}
<<<END WATCHDOG TICK>>>
EOF
}

build_close_confirm_prompt() {
  local ready="$1"
  local in_progress="$2"
  local quality_due="$3"
  local prompt_marker="$4"
  cat <<EOF
<<<WATCHDOG EPIC CLOSED>>>
Watchdog action required for session '$SESSION':
Epic '$EPIC' is CLOSED, but controller verification is still required before the watchdog can be stopped.
Watchdog marker: ${prompt_marker}

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
   ${SCRIPT_DIR}/stop.sh --session $SESSION

This is not FYI. Controller action is required on every closed-epic tick until the watchdog is stopped.
Watchdog marker: ${prompt_marker}
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

  controller_pane_info="$(find_controller_pane || true)"
  controller_pane_id="$(printf '%s\n' "$controller_pane_info" | head -n1)"
  controller_pane_index="$(printf '%s\n' "$controller_pane_info" | sed -n '2p')"
  controller_pane_ref="$(printf '%s\n' "$controller_pane_info" | sed -n '3p')"
  controller_pane_title="$(printf '%s\n' "$controller_pane_info" | sed -n '4p')"
  controller_pane_command="$(printf '%s\n' "$controller_pane_info" | sed -n '5p')"
  prompt_marker="watchdog:${SESSION}:$(date +%s):$$:${RANDOM}"
  if [[ -z "${controller_pane_id:-}" ]]; then
    log "no-controller-pane regex=$CONTROLLER_TITLE_REGEX"
  else
    if [[ "$epic_status" == "CLOSED" ]]; then
      if [[ "$EXIT_MODE" == "auto" ]]; then
        EXIT_REASON="epic closed with exit-mode=auto"
        log "epic-closed exiting epic=$EPIC mode=auto"
        exit 0
      fi
      close_prompt="$(build_close_confirm_prompt "$ready_csv" "$in_progress_csv" "$quality_due_csv" "$prompt_marker")"
      send_prompt_to_controller \
        "$controller_pane_id" \
        "$controller_pane_index" \
        "$controller_pane_ref" \
        "$controller_pane_title" \
        "$controller_pane_command" \
        "$close_prompt" \
        "$prompt_marker"
      log "epic-closed notify-sent pane_id=$controller_pane_id mode=confirm"
    else
      prompt="$(build_prompt "$ready_csv" "$in_progress_csv" "$quality_due_csv" "$prompt_marker")"
      send_prompt_to_controller \
        "$controller_pane_id" \
        "$controller_pane_index" \
        "$controller_pane_ref" \
        "$controller_pane_title" \
        "$controller_pane_command" \
        "$prompt" \
        "$prompt_marker"
      log "prompt-sent pane_id=$controller_pane_id"
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
