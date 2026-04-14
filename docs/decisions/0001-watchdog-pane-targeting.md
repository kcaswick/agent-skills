# ADR 0001: Use tmux Pane IDs for Watchdog Robot-Send Targeting

**Date:** 2026-04-14  
**Status:** Accepted  
**Deciders:** Controller (PinkHarbor), Codex (TanPike)

## Context

The `controller-proxy-watchdog` skill sends coordination prompts to a controller pane using `ntm --robot-send --panes=<target>`. When the watchdog runs as a window within the same tmux session as agent panes, pane index collisions occur.

**Problem:** tmux pane indices (0, 1, 2, ...) repeat across windows in the same session. Using `--panes=1` matches ALL panes with index 1, including:
- The controller pane (window 1, pane 1)
- The watchdog pane (window 2, pane 1)

This causes watchdog ticks to be sent to unintended panes or fail silently.

## Decision

Use **tmux pane IDs** (`%0`, `%1`, `%27`, etc.) instead of pane indices for `ntm --robot-send --panes=` targeting.

Pane IDs are globally unique within a session and uniquely identify a single pane regardless of window boundaries.

## Rationale

1. **Uniqueness:** Pane IDs are guaranteed globally unique across the entire session. Indices repeat across windows.
2. **Simplicity:** No need for type filtering (`--type=claude`) or complex discovery heuristics. Direct pane targeting is sufficient.
3. **Robustness:** Works correctly with multiple agents of the same type in the primary window.
4. **Architecture preservation:** Allows watchdog to run as a window within the controlled session (preferred architecture) without collision risks.

## Implementation

### Watchdog Discovery
```bash
# Get controller pane ID across all windows in the session
controller_pane_id=$(tmux list-panes -a -F '#{pane_id}|#{pane_title}' \
  | rg -i "$CONTROLLER_TITLE_REGEX" \
  | head -n1 \
  | cut -d'|' -f1)
```

### Watchdog Send
```bash
ntm --robot-send="$SESSION" --panes="$controller_pane_id" --msg="$prompt" --json
```

## Alternatives Considered

1. **Type filtering (`--type=claude`):** Would fail with multiple agents of same type
2. **Separate session:** Adds architectural complexity, breaks established pattern
3. **Index + window scoping:** More complex, still fragile if windows are reordered

## Consequences

- ✅ Eliminates pane collision issues
- ✅ Preserves same-session watchdog architecture
- ✅ Simpler code than type-filtering approach
- ✅ Works with any number of agents of any type
- ⚠️ Requires `tmux list-panes -a` (lists all panes across all windows)

## References

- `controller-proxy-watchdog/scripts/watchdog_controller_proxy.sh`
- `ntm --robot-send` documentation
- tmux pane ID format: `%<number>`
