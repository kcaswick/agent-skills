---
name: pane-send-protocol
description: Protocol for sending automated messages to tmux panes in multi-agent workflows. Covers the <<<...>>> envelope convention, pane ID targeting (not index), and when to send directly vs. route through Agent Mail. Use whenever an agent or script sends a message to another pane via ntm --robot-send.
---

# Pane Send Protocol

Two rules govern every automated pane send in a multi-agent workflow.

## Rule 1: Envelope Rule

Every automated pane send wraps its **entire message body** in `<<<` ... `>>>`
delimiters. This makes automated input unambiguously distinct from any in-flight
user typing that may be in the same pane.

```
<<<LABEL optional-inline-content>>>
body of the message
<<<END LABEL>>>
```

- The opening `<<<LABEL>>>` and closing `<<<END LABEL>>>` are a **single
  envelope per message** — they are start/end bounds, not separate paired tokens
  the recipient searches for independently.
- For short, single-line messages: a self-contained `<<<LABEL content>>>` with
  no separate closer is sufficient.
- For multi-line messages: the `<<<LABEL>>>` ... `<<<END LABEL>>>` form clearly
  bounds the entire body.
- Descriptive prefixes inside the envelope (e.g. `<<<CHECK MAIL paneN bd-xxx
  done>>>`) are part of the message content, not a second nesting level.

Examples of correctly-formed envelopes:

```
# Short ping (no closer needed):
<<<CHECK MAIL pane3 bd-abc done>>>

# Multi-line tick:
<<<WATCHDOG TICK>>>
State: ready_beads=bd-a in_progress=bd-b
Action: assign bd-a to pane2
<<<END WATCHDOG TICK>>>
```

## Rule 2: Direct Ping vs. Agent Mail Body

Choose based on message size and complexity:

| Message type | Send via |
|---|---|
| Short, self-contained (status ping, single-action prompt, completion notification) | Direct `ntm --robot-send` with full content in the `<<<...>>>` envelope |
| Long, detailed handoff (findings, multi-step instructions, large artifacts) | Put body in Agent Mail (bead/topic-specific subject), send a short `<<<CHECK MAIL ...>>>` ping to the recipient pane; note in the ping that source of truth is the mail body |

Treat direct pings as notification-only when the content is in Agent Mail. The
receiver must fetch the inbox before marking work complete.

## Rule 3: Targeting

Always use the tmux **pane ID** (`%27`, `%31`, …) for `--panes=`, never the
pane index. Pane IDs are globally unique within a session; indices repeat across
windows. See ADR 0001 for the rationale.

Pane ID discovery:
```bash
tmux list-panes -a -F '#{pane_id}|#{pane_title}' | rg -i "<title-regex>"
```

Send command:
```bash
ntm --robot-send=<session> --panes=<pane-id> --msg="<<<LABEL content>>>" --json
```

Validate the JSON result: `success` must be `true`, the target pane ID must
appear in `successful`, and `failed` must be empty.

Always run `agent-pane-readiness-check` before sending.

## Capability References

- **Pane orchestration** — default adapter: `ntm`
- **Async agent messaging** — default adapter: `agent-mail`
  (only when the body-in-mail branch is chosen)
