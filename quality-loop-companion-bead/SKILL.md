---
name: quality-loop-companion-bead
description: Pattern for tracking quality loops (self-review, cross-review, random exploration) as companion beads linked to implementation beads. Use after completing any substantial implementation bead to ensure quality loops are explicitly tracked and closed with findings.
---

# Quality Loop Companion Bead

Quality loops are tracked as regular beads, not ad-hoc notes.

## Companion Bead Convention

For each implementation bead that needs post-implementation quality loops,
ensure there is an **open** companion bead named:

```
Quality loops for <impl-bead-id>
```

Rules:
- If no open companion bead exists, create one before assigning or running
  any loop work.
- A previously **closed** `Quality loops for <id>` bead does **not** satisfy
  this requirement for a reopened implementation bead. Create a new open
  companion bead for the new loop cycle.
- Close the companion bead only after all required loops have run and findings
  are recorded (or explicitly recorded as "no findings").

## Required Loops

Run all three for each substantial implementation bead:

1. **Self-review** — Reread all changes with fresh eyes, looking for bugs,
   regressions, and missed edge cases.
2. **Cross-review** — If other agents are active, request cross-review via
   Agent Mail. Use `pane-send-protocol` for the handoff.
3. **Random exploration** — Run a structured review across the full diff (e.g.
   `/review`). This catches interaction bugs between concurrent agent work.
   Also trace execution flows through changed code paths.

Record findings with `severity + file:line`. For anything outside current scope,
create a follow-up bead or GitHub issue and link it.

## Closure Requirements

Close the companion bead with a summary that includes:
- Validation pass results (linter, type checker, tests)
- Non-blocking findings (with links to follow-up beads/issues)
- Deferred follow-ups with issue/bead links

For loop assignments sent to worker panes, require:
- Agent Mail findings body
- An explicit `ntm --robot-send` ping back to the controller (see
  `pane-send-protocol`) before marking the loop closed

## Capability Reference

- **Task tracker** — default adapter: `beads-workflow`
  (`br create`, `br update`, `br close`, `br sync --flush-only`)
