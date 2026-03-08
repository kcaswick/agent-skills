---
name: pr-review-comment-response
description: Triage, track, and respond to GitHub PR review comments with explicit dispositions (adopt, adapt, defer, decline, addressed, superseded) and evidence-backed replies. Use when handling unresolved PR feedback, running review rounds, mapping comments to beads/issues, or preparing maintainable reply workflows without resolving threads.
---

# PR Review Comment Response

## Overview
Use this skill to process PR review comments end-to-end: inventory unresolved threads, decide disposition per comment, map work to beads/issues, verify evidence, and post concise replies.

Thread-resolution rule:
- Agents may post replies to review threads.
- Agents using this skill must not resolve review threads.
- This skill is for responding, not for acting as the reviewer who decides whether a thread is resolved.
- Treat `resolveReviewThread` as forbidden in this workflow.

## Dependencies
Required:
- `ntm`
- `beads-workflow`
- `agent-mail`

Strongly recommended:
- `agent-swarm-workflow`

Optional:
- `controller-proxy-watchdog`
- `cass`
- `bv`
- `planning-workflow`

## Allowed Tools
GitHub tools:
- `gh api graphql`
- `gh issue view`
- `gh issue create`

Coordination and tracking tools:
- `ntm status`, `ntm view`, `ntm send`, `ntm interrupt`, `ntm history`
- `br ready`, `br show`, `br create`, `br update`, `br close`, `br search`, `br sync --flush-only`

## Inputs
Collect these before acting:
- PR number
- scope: specific comment IDs or all unresolved threads
- action mode: inventory-only, reply-only, implement-and-reply

## Workflow
1. Build thread inventory
- Query review threads and unresolved status for the PR.
- Keep a table with: comment ID (`r...`), thread ID, severity, status (resolved/unresolved), URL.

2. Triage each comment
- Assign one disposition:
  - `adopt`: implement as requested.
  - `adapt`: implement with bounded design changes.
  - `addressed`: already fixed in current branch.
  - `superseded`: obsolete because architecture changed.
  - `defer`: out-of-scope for current round; create bead/issue.
  - `decline`: not adopting; provide rationale.

3. Track in beads before coding
- Create/increment round epic.
- Add per-comment beads with thread links.
- Prefer parent-child grouping for round structure.
- When deferring, include branch-specific defer reason and explicit destination bead/issue.

4. Implement and verify
- Preserve required behavioral invariants for the code path.
- Add targeted tests that fail on regression.
- Capture validation evidence (`ruff`, targeted `pytest`, full `pytest` as needed).

5. Run quality loops
- Self-review, cross-review, random/adversarial exploration.
- Record findings with severity and `file:line` references.
- If non-blocking but out of scope, create follow-up issue/bead and link it.

6. Reply on GitHub
- Keep replies concise and factual.
- Include disposition, what changed, where changed, and test evidence.
- Include commit hash when available.

7. Leave thread resolution to the reviewer or repo owner
- Post the reply text and supporting evidence.
- If a thread is deferred, reply with the destination bead/issue and leave it open.
- Report which threads are now reply-ready for reviewer/repo-owner resolution.

## Reply Templates
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

## GitHub GraphQL Snippets
List unresolved thread anchors:
```bash
gh api graphql -f query='query { repository(owner:"<owner>", name:"<repo>") { pullRequest(number:<n>) { reviewThreads(first:100) { nodes { isResolved comments(first:1){ nodes { databaseId url }}}}}}}' \
| jq -r '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved==false) | .comments.nodes[0] | "r\(.databaseId) \(.url)"'
```

Reply to thread:
```bash
gh api graphql -f query='mutation($thread:ID!, $body:String!) { addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$thread, body:$body}) { comment { id url } } }' \
  -F thread='<thread_id>' -F body='<reply>'
```

## Output Contract
Return:
- disposition table per comment ID
- bead/issue links created or referenced
- reply text posted (or draft text if inventory-only)
- explicit list of replied threads and still-open threads
- validation evidence summary for any `addressed`/`adopt` claims

## Guardrails
- Do not claim "addressed" without concrete code/test evidence.
- Do not call `resolveReviewThread`.
- Do not describe a workflow step as "reply-and-resolve"; agents reply only.
- Do not let reply text drift from actual committed state.
- Keep scratch artifacts in `temp/` or `/tmp/`, not `docs/`.
