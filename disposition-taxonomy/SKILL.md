---
name: disposition-taxonomy
description: Six-disposition taxonomy for classifying review feedback (PR comments, RFC feedback, design review notes) and evidence-backed reply structure. Use when triaging any review-style feedback that requires an explicit disposition and a structured written response.
---

# Disposition Taxonomy

A generic taxonomy for classifying review feedback and drafting evidence-backed
replies. Applies to PR review comments, RFC feedback, design review notes, or
any structured review round.

## Dispositions

| Disposition | Meaning |
|---|---|
| **adopt** | Implement exactly as requested |
| **adapt** | Implement with adjusted design constraints (explain why) |
| **addressed** | Already fixed in current branch — cite commit/code |
| **superseded** | Replaced by newer architecture — explain what replaced it |
| **defer** | Out of scope for this round — create tracking item with reason |
| **decline** | Not adopting — explain rationale |

Present the full disposition table before acting. Wait for confirmation unless
the caller specified auto-implementation mode.

## Reply Structure

Four-line structure per feedback item:

- **Line 1:** Disposition status — `Implemented` | `Deferred` | `Declined` | `Superseded` | `Already addressed`
- **Line 2:** Concrete change surface — file/module and behavior change
- **Line 3:** Validation evidence — test/lint scope and results
- **Line 4 (optional):** Commit hash or reference

## Reply Templates

**Implemented:**
```
Implemented in `<commit>`. Updated `<file>` to `<behavior change>`,
with coverage in `<test file>`. Validation: `<commands/results>`.
```

**Deferred:**
```
Deferred to `<tracking-id>: <title>` under `<parent>`.
This will be handled in a follow-up focused on `<scope>`.
```

**Declined:**
```
Decline for current scope: `<reason>`.
Current approach preserves `<invariant/constraint>`.
```

**Superseded:**
```
Superseded by later implementation in `<file/module>`,
which now handles `<behavior>`.
```

**Already addressed:**
```
Already addressed in `<commit>` / `<file>`.
See `<file:line>` for the fix.
```

## Examples

```
**Implemented.** Refactored lifecycle management in `src/modal.py` —
container startup now uses explicit state machine with round-3 tracking.
Validated: ruff clean, pytest tests/test_modal.py green. Commit: 82d4679
```

```
**Deferred.** Tracked as bd-1pk under epic bd-159 — concurrency stress
coverage is out of scope for this PR. GitHub issue #7 created for follow-up.
```

## Rules

- Do not claim `addressed` without concrete code/test evidence (commit hash or
  file:line).
- Do not let reply text drift from actual committed state; re-read the diff
  before drafting.
- Never auto-resolve review threads; leave resolution to the reviewer.
