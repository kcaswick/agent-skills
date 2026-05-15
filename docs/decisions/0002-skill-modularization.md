# ADR 0002: Separate Pattern Skills from Tool/Runner Skills

**Date:** 2026-05-15
**Status:** Accepted
**Deciders:** lablua@gmail.com (human), Ultraplan refinement session

## Context

This repo holds two skills (`pr-review-comment-response`,
`controller-proxy-watchdog`). Each interleaves a reusable *pattern* (workflow,
taxonomy, output contract) with *tool-specific commands*.

Specific evidence of mixing:

- `pr-review-comment-response/SKILL.md` (lines 67–82, 98–102, 148–193, 212–220):
  the Phase 1–7 workflow, disposition taxonomy, and reply structure are entangled
  with `gh api graphql` calls, `br create`/`br update`/`br close` commands,
  `ntm` spawning, and Agent Mail MCP references.

- `controller-proxy-watchdog/SKILL.md` (lines 28–35, 47–100, 127–146): the
  tick cadence, pane-readiness check, handoff semantics, and exit-mode policy
  are entangled with `tmux list-panes`, `tmux capture-pane`, `ntm --robot-send`,
  `br` state reads, and a 720-line bash implementation in `scripts/`.

Several building blocks are already duplicated or cross-cited between just these
two skills:

1. **Pre-send pane readiness check** — watchdog SKILL.md §47–87; implicitly
   required by PR-review multi-agent mode but only documented in the watchdog.
2. **Pane-send envelope (`<<<...>>>`)** — watchdog handoff section and
   `scripts/watchdog_controller_proxy.sh` lines 481–536. Originally documented
   as paired open/close markers (`<<<CHECK MAIL>>> ... <<<END CHECK MAIL>>>`);
   the actual semantics is one envelope per message with no paired closer.
3. **Direct-ping vs. Agent Mail body decision** — the watchdog states "always
   Agent Mail body" (overly strict); short status pings should go direct.
4. **Quality-loop companion bead** — cross-cited between both skills (watchdog
   §127–146, PR-review §119–134).
5. **Disposition taxonomy + reply structure** — PR-review §67–82 and §148–193;
   reusable beyond PRs (RFC/design review).

Without extraction, each new pattern skill will re-inline these building blocks,
and a tool change (e.g. `br` replacement, harness scheduler replacing the bash
watchdog loop) forces a full rewrite of every consumer.

## Decision

Split skills into two layers:

1. **Pattern skills** (live in this repo): describe the workflow in capability
   terms. Reference capabilities (task tracker, agent messaging, pane
   orchestration, scheduled tick) rather than concrete tool commands.

2. **Tool/runner skills**: concrete commands. For tools already covered by
   external adapter skills (`beads-workflow`, `agent-mail`, `ntm`), reference
   those by capability. For tools not covered externally (the watchdog bash
   scripts, which pre-date any harness-level scheduler), create a runner skill
   in this repo.

**Constraint:** before removing any inline tool guidance from a SKILL.md,
audit the external skill at its installed path. If the external skill is silent
on the topic, keep the guidance here — either in the pattern skill or in the
relevant extracted block.

## Reusable Building Blocks Identified

These become standalone block skills:

| Block skill | Source(s) | Consumers |
|---|---|---|
| `agent-pane-readiness-check` | watchdog SKILL.md §47–87 | coordination-watchdog-pattern, pr-review-comment-response (multi-agent mode) |
| `pane-send-protocol` | watchdog SKILL.md §89–100 + scripts lines 481–536 | coordination-watchdog-pattern, pr-review-comment-response (multi-agent mode) |
| `quality-loop-companion-bead` | watchdog SKILL.md §127–146, pr-review SKILL.md §119–134 | both pattern skills |
| `disposition-taxonomy` | pr-review SKILL.md §67–82, §148–193 | pr-review-comment-response; future RFC/design-review skills |

## Target Shape

```
coordination-watchdog-pattern/   (renamed from controller-proxy-watchdog, rewritten)
└── SKILL.md       (pure pattern, capability refs)

ntm-watchdog-runner/             (new — scripts extracted from controller-proxy-watchdog)
├── SKILL.md
└── scripts/      (start.sh, stop.sh, status.sh, watchdog_controller_proxy.sh)

pr-review-comment-response/      (rewritten)
├── SKILL.md       (pure pattern, capability refs)
└── agents/openai.yaml  (unchanged)

agent-pane-readiness-check/      (new extracted block)
pane-send-protocol/              (new extracted block)
quality-loop-companion-bead/     (new extracted block)
disposition-taxonomy/            (new extracted block)

docs/decisions/
├── 0001-watchdog-pane-targeting.md  (path references updated)
└── 0002-skill-modularization.md     (this file)
```

Dependency edges (solid = required, dashed = opt-in based on environment):

```
pr-review-comment-response ──► disposition-taxonomy
                           ──► quality-loop-companion-bead
                           ──► pane-send-protocol
                           ──► agent-pane-readiness-check
                           ──► external: beads-workflow, agent-mail, ntm, gh

coordination-watchdog-pattern ──► agent-pane-readiness-check
                              ──► pane-send-protocol
                              ──► quality-loop-companion-bead
                              ──► external: beads-workflow, agent-mail, ntm
                              --► ntm-watchdog-runner  (opt-in: environments without native scheduler)
                              --► harness ScheduleWakeup/CronCreate  (opt-in: harness-equipped environments)

ntm-watchdog-runner ──► external: ntm, beads-workflow
```

## What the Split Buys

- **Pattern survives tool churn.** Swap `br` for another tracker: update the
  capability row, not the workflow doc.
- **Reused blocks stop drifting.** Pane-readiness and handoff semantics are
  canonical in one place; consumers cite them rather than copy them.
- **Harness-aware skills.** The watchdog pattern works with either
  `ntm-watchdog-runner` (bash loop) or a harness `ScheduleWakeup`/`CronCreate`
  (no bash loop needed). The runner skill is opt-in.
- **Faster authoring of future pattern skills.** Skill #3, #4, #5 compose
  existing blocks rather than re-inlining commands.

## What It Costs

- **Indirection for readers.** Following capability references requires hopping
  to the block skill. Mitigation: each pattern skill's quickstart section keeps
  one concrete command example per capability, marked as `(default: <adapter>)`.
- **Cross-repo coordination.** Adapter skills live outside this repo and are
  not co-versioned. This is already the status quo.
- **Threshold effect.** Five extracted blocks for two pattern skills is steep.
  Pays off at skill #3; at skill #2 it's break-even.

## Alternatives Considered

1. **Status quo** — works for two skills, doesn't scale. Each new skill
   re-copies building blocks; tool changes force full rewrites.
2. **Extract blocks only, don't split scripts** — leaves the
   harness-scheduler path blocked; `ntm-watchdog-runner` must exist for
   environments that need the bash loop.
3. **Inline everything in each skill** — current state; the problem this ADR
   addresses.

## Consequences

The directory shape in "Target Shape" above applies after this refactor.
External skill coverage must be audited at each call site; if silent on a
topic, the content stays in this repo.

After this change, no file in this repo should reference `controller-proxy-watchdog`
(the old directory name). ADR 0001 path references are updated in step 6.

## References

- [ADR 0001: Use tmux Pane IDs for Watchdog Robot-Send Targeting](0001-watchdog-pane-targeting.md)
- `agent-pane-readiness-check/SKILL.md`
- `pane-send-protocol/SKILL.md`
- `quality-loop-companion-bead/SKILL.md`
- `disposition-taxonomy/SKILL.md`
- `coordination-watchdog-pattern/SKILL.md`
- `ntm-watchdog-runner/SKILL.md`
- `pr-review-comment-response/SKILL.md`
