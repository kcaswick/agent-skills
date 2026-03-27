---
name: pr-review-comment-response
description: Triage, track, and respond to GitHub PR review comments with explicit dispositions (adopt, adapt, defer, decline, addressed, superseded) and evidence-backed replies. Use when handling unresolved PR feedback, running review rounds, mapping comments to beads/issues, or preparing maintainable reply workflows without resolving threads.
argument-hint: <PR-number> [comment-IDs|all]
allowed-tools: "Bash(gh api graphql *), Bash(gh pr view *), Bash(gh pr diff *), Bash(gh pr checks *), Bash(gh issue view *), Bash(gh issue create *), Bash(br *), Bash(bv --robot-*), Read, Grep, Glob, Edit"
---

# PR Review Comment Response

Handle a round of PR review comments for PR **$ARGUMENTS**.

---

## Ground Rules

- **Never auto-resolve PR threads.** Treat `resolveReviewThread` as forbidden in this workflow. Resolve only on explicit maintainer instruction in this session, and re-query thread status before doing so.
- **Never delete files** without express permission.
- Keep assignment/completion state in beads and PR comments.
- Use Agent Mail for coordination notes — never use `docs/` for temporary scratch. Ephemeral scratch goes in `temp/` if needed.
- Do not claim "addressed" without concrete code/test evidence.
- Do not let reply text drift from actual committed state.

---

## Inputs

Collect these before acting:

- **PR number** (from `$ARGUMENTS` or ask)
- **Scope:** specific comment IDs or all unresolved threads
- **Action mode:** inventory-only, reply-only, or implement-and-reply

---

## Phase 1: Inventory

Query all unresolved review threads on the PR.

```graphql
query($owner:String!, $repo:String!, $pr:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      reviewThreads(first:100) {
        nodes {
          id
          isResolved
          comments(first:10) {
            nodes { id body author { login } path line createdAt }
          }
        }
      }
    }
  }
}
```

Build a worklist keyed by thread ID. For each thread, capture:
- Thread node ID (for replies)
- First comment body, author, file path, line
- Any follow-up comments in the thread
- Comment ID (`r...`), severity, status (resolved/unresolved), URL

If specific comment IDs were provided in `$ARGUMENTS`, filter to only those. Otherwise process all unresolved threads.

---

## Phase 2: Triage

Classify each thread into a disposition:

| Disposition | Meaning |
|---|---|
| **adopt** | Implement exactly as requested |
| **adapt** | Implement with adjusted design constraints (explain why) |
| **addressed** | Already fixed in current branch — cite commit/code |
| **superseded** | Replaced by newer architecture — explain what replaced it |
| **defer** | Out of scope for this PR — create bead/issue with reason |
| **decline** | Not adopting — explain rationale |

Present the disposition table before proceeding. Wait for confirmation unless action mode is `implement-and-reply`.

---

## Phase 3: Track in Beads

Use `/beads-workflow` patterns:

1. Create or find the **review-round epic** for this PR (e.g., `PR #N review round M`).
2. For each `adopt`/`adapt` comment, create an implementation bead:
   - Title references the thread (e.g., `[rXXX] <summary of request>`).
   - Description includes the reviewer's comment verbatim plus implementation plan.
   - Parent link to the review-round epic.
3. For each `defer` comment, create a deferred bead:
   - Include branch-specific defer reason and explicit destination bead/issue.
   - Link to a GitHub issue if cross-PR.
4. Mark beads `in_progress` as work begins.

```bash
br create --title="[rXXX] <summary>" --type=task --priority=2
br update <id> --status=in_progress
```

---

## Phase 4: Implement

For each `adopt`/`adapt` bead:

1. **Scope to comment intent.** Do not expand beyond what was requested.
2. **Preserve critical behavior invariants** while changing internals.
3. **Add targeted tests** that would fail on regression of the fix.
4. Run project quality gates after each change:
   - Linter/formatter
   - Type checker
   - Test suite

---

## Phase 5: Quality Loops

Use `/agent-swarm-workflow` quality-loop structure:

1. **Self-review** — Reread all changes with fresh eyes, looking for bugs/regressions.
2. **Cross-review** — If other agents are active, request cross-review via Agent Mail.
3. **Random exploration** — Run `/review` on the PR to get a structured assessment across the full diff. This reviews all PR changes (not just yours), which is useful for catching interaction bugs between concurrent agent work. Also trace execution flows through changed code paths.

Record findings with `severity + file:line`. For anything outside current scope, create a follow-up bead or GitHub issue and link it.

Create a companion quality-loop bead for substantial implementation beads. Close with:
- Validation pass results
- Non-blocking findings
- Deferred follow-ups with issue/bead links

---

## Phase 6: Reply on GitHub

For each thread, post a reply via GraphQL:

```graphql
mutation($thread:ID!, $body:String!) {
  addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$thread, body:$body}) {
    comment { id url }
  }
}
```

### Reply Structure

- **Line 1:** Disposition status — `Implemented` | `Deferred` | `Declined` | `Superseded` | `Already addressed`
- **Line 2:** Concrete change surface — file/module and behavior change
- **Line 3:** Validation evidence — test/lint scope and results
- **Line 4 (optional):** Commit hash

### Reply Templates

Implemented:
```md
Implemented in `<commit>`. Updated `<file>` to `<behavior change>`, with coverage in `<test file>`.
Validation: `<commands/results>`.
```

Deferred:
```md
Deferred to `<bead-or-issue-id>: <title>` under `<epic-or-parent>`. This will be handled in a follow-up PR focused on `<scope>`.
```

Declined:
```md
Decline for current scope: `<reason>`. Current approach preserves `<invariant/constraint>`.
```

Superseded:
```md
Superseded by later implementation in `<file/module>`, which now handles `<behavior>`.
```

### Examples

```
**Implemented.** Refactored lifecycle management in `src/modal.py` —
container startup now uses explicit state machine with round-3 tracking.
Validated: ruff clean, pytest tests/test_modal.py green. Commit: 82d4679
```

```
**Deferred.** Tracked as bd-1pk under epic bd-159 — concurrency stress
coverage is out of scope for this PR. GitHub issue #7 created for follow-up.
```

### Thread Resolution

After posting replies, report which threads are now reply-ready for reviewer/repo-owner resolution. Do not resolve threads yourself — leave that to the reviewer.

---

## Phase 7: Close Out

1. Close completed beads:
   ```bash
   br close <id> --reason "Implemented and replied on PR"
   br sync --flush-only
   ```
2. Update epic with summary of round outcomes.
3. If using Agent Mail, send completion summary to thread.
4. Stage and commit bead changes with code changes.

---

## Multi-Agent Mode

For larger review rounds with many threads:

1. Use `/ntm` to spawn agents and assign comment subsets.
2. Use `/agent-mail` for file reservations and coordination:
   ```
   file_reservation_paths(project_key, agent_name, ["src/**"], reason="PR-N-review")
   ```
3. Use `/agent-swarm-workflow` assignment discipline — each agent claims specific beads.
4. Optionally use `/controller-proxy-watchdog` for automated tick-driven coordination.
5. For very large rounds, use `/planning-workflow` to plan the approach before creating beads.

---

## Output Contract

Return:
- Disposition table per comment ID
- Bead/issue links created or referenced
- Reply text posted (or draft text if inventory-only)
- Explicit list of replied threads and still-open threads
- Validation evidence summary for any `addressed`/`adopt` claims

---

## Dependency Skills

### Required

| Skill | Role in this workflow |
|---|---|
| **ntm** | Pane orchestration: spawn/view/send/interrupt agents |
| **beads-workflow** | Comment-to-bead tracking, epics, defer/close lifecycle |
| **agent-mail** | Cross-agent coordination and handoffs without polluting files |

### Strongly Recommended

| Skill | Role in this workflow |
|---|---|
| **agent-swarm-workflow** | Assignment discipline, quality-loop execution structure |

### Optional

| Skill | When to use |
|---|---|
| **controller-proxy-watchdog** | Automated tick-driven coordination for multi-agent rounds |
| **cass** | Search agent session history for prior context |
| **bv** | Graph-aware triage when review touches many beads |
| **planning-workflow** | Only for larger review rounds requiring upfront design |

---

## Command Skeletons

### List unresolved threads
```bash
gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!) {
    repository(owner:$owner,name:$repo) {
      pullRequest(number:$pr) {
        reviewThreads(first:100) {
          nodes { id isResolved comments(first:1) { nodes { id body path line } } }
        }
      }
    }
  }' -f owner=OWNER -f repo=REPO -F pr=NUMBER | jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved==false)'
```

### Post thread reply
```bash
gh api graphql -f query='
  mutation($thread:ID!,$body:String!) {
    addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$thread,body:$body}) {
      comment { id url }
    }
  }' -f thread=THREAD_NODE_ID -f body="Reply text here"
```
