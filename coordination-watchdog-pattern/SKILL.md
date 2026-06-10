---
name: coordination-watchdog-pattern
description: "Tick-driven pattern that periodically notifies a controller pane to coordinate bead assignments and quality loops. Describes what to send and when — execution is handled by ntm-watchdog-runner (bash) or a harness scheduler (ScheduleWakeup/CronCreate)."
---

# Coordination Watchdog Pattern

A background watchdog that sends periodic coordination prompts into a
controller pane. The watchdog does **not** assign beads directly — it
prods the controller, which decides how to assign work.

This skill describes the *pattern*: cadence, state, prompt content, and
completion semantics. Execution is handled by:
- **`ntm-watchdog-runner`** — bash loop in environments without a native
  scheduler
- **Harness primitives** (`ScheduleWakeup` / `CronCreate`) — in harness-equipped
  environments; implement the same tick logic without the bash loop

## Capability Table

| Capability | Default adapter |
|---|---|
| Task tracker (epics, child tasks, deps) | `beads-workflow` |
| Async agent messaging | `agent-mail` |
| Pane orchestration / robot-send | `ntm` |
| Scheduled tick | harness `ScheduleWakeup`/`CronCreate` **or** `ntm-watchdog-runner` |

## Tick Cadence

Default interval: **420 seconds**. Override per deployment. The watchdog sends
one tick prompt per interval; it does not send if the previous tick's prompt
was not consumed (detected via the watchdog marker).

## Watchdog State

On each tick, compute three bead state lists from the managed bead set:

- **ready** — beads with status READY (all dependencies satisfied)
- **in_progress** — beads with status IN_PROGRESS
- **quality_due** — in_progress beads that need post-implementation quality loops
  (no open `Quality loops for <bead>` companion bead exists)

## Prompt Content (per tick)

Send one `<<<WATCHDOG TICK>>>` envelope to the controller pane containing:

```
<<<WATCHDOG TICK>>>
Watchdog tick for session '<session>'.
Use pane captures as source of truth (not ntm status/health), then coordinate assignments.
Watchdog marker: <marker>

State:
- ready_beads: <csv or "none">
- in_progress_beads: <csv or "none">
- quality_loops_due: <csv or "none">

Actions:
1. Verify active worker state with pane captures and br show.
2. Assign ready implementation beads by dependency order and conflict safety.
   Require an Agent Mail report for each assignment, and tell each worker the
   exact ntm --robot-send command for the notification ping (see pane-send-protocol).
3. For workers blocked by deps/conflicts, assign targeted review tasks.
4. Run post-bead quality loops for each bead in quality_loops_due (see quality-loop-companion-bead).
5. For each loop/review assignment, require Agent Mail findings plus the notification
   ping before closure.
6. Track completion in beads by closing each quality-loop bead with findings summary.
7. Report assignments and completion handoffs.
Watchdog marker: <marker>
<<<END WATCHDOG TICK>>>
```

The **watchdog marker** (`watchdog:<session>:<timestamp>:<pid>:<random>`) is
embedded twice — at the start and end of the body — so the watchdog can detect
whether the controller consumed the prompt (by checking that the marker is no
longer visible in the pane buffer). If the marker is still present on the next
tick, the prompt was not submitted and the watchdog skips sending until it is.

## Pre-Send Requirements

Before sending any tick prompt, run `agent-pane-readiness-check` to confirm
the controller pane is at an active agent prompt. Follow `pane-send-protocol`
for targeting (always use pane ID, not pane index) and envelope formatting.

## Closed-Epic Behavior

When the epic is closed:

- **`confirm` mode (default):** send a recurring `<<<WATCHDOG EPIC CLOSED>>>`
  prompt on each tick. Include the current bead state and an explicit instruction
  that the controller must verify completion and stop the watchdog via
  explicit controller action. To prevent indefinite token usage, this mode has a
  safety limit of 10 ticks before requiring human intervention to continue.
- **`auto` mode (autonomous exit):** stop immediately when the epic is closed.

The `<<<WATCHDOG EPIC CLOSED>>>` envelope contains the same state fields as the
tick prompt, plus an explicit stop command and a notice of the remaining ticks
before the safety limit is reached.

## Quality Loop Tracking

See `quality-loop-companion-bead`. The watchdog prompt's `quality_loops_due`
list drives which beads need loop work. The controller is responsible for
creating companion beads and closing them with findings.

## Handoff Pattern

See `pane-send-protocol`. Assignment results go in Agent Mail (for detailed
findings) with a short `<<<CHECK MAIL ...>>>` ping to the controller. The
source of truth is the Agent Mail body; pings are notification-only.

## Dependency Skills

### Required (block skills)

| Skill | Role |
|---|---|
| **agent-pane-readiness-check** | Pre-send pane verification before each tick |
| **pane-send-protocol** | Envelope convention, pane ID targeting, direct vs. mail decision |
| **quality-loop-companion-bead** | Companion bead rule and loop triad that ticks drive |

### Execution (pick one per environment)

| Skill | When to use |
|---|---|
| **ntm-watchdog-runner** | No native harness scheduler available |
| Harness `ScheduleWakeup`/`CronCreate` | Harness provides scheduling primitives |

### External Adapters

| Capability | Skill |
|---|---|
| Task tracker | `beads-workflow` |
| Async messaging | `agent-mail` |
| Pane orchestration | `ntm` |
