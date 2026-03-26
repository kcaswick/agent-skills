# AGENTS.md

This file provides guidance to AI coding agents working in this repository.

## What This Repo Is

A skill registry for Claude Code and AI coding agents. Each top-level directory is a self-contained skill — a reusable workflow that agents invoke to handle complex multi-step tasks (PR review automation, background watchdog coordination, etc.). Skills are documentation + bash scripts, not libraries.

## Critical Rules

- **Never delete files** without express permission — not even files you created.
- **Never run destructive git commands** (`git reset --hard`, `git clean -fd`, `rm -rf`) unless the user provides the exact command and confirms they understand the consequences.
- **Default branch is `main`**, never `master`.
- **No script-based code changes.** Always make changes manually — no regex transforms on code files.
- **No file proliferation.** Edit existing files in place. Never create `_v2`, `_improved`, `_enhanced` variants. New files only for genuinely new functionality.
- **No backwards-compatibility shims.** Early development, no users. Do it the right way with no tech debt.
- **Multi-agent environment:** Other agents may be editing files concurrently. Never stash, revert, or overwrite changes you didn't make — treat them as your own.

## Skill Anatomy

```
skill-name/
├── SKILL.md              # Required — frontmatter + operational instructions
├── scripts/              # Optional — bash implementations
├── agents/               # Optional — agent configs (openai.yaml, etc.)
└── references/           # Optional — docs loaded on demand
```

### SKILL.md Frontmatter

```yaml
---
name: skill-name                    # Required — skill identifier
description: "What it does..."      # Required — triggers skill invocation
argument-hint: <args>               # Functional — tells CLI what to pass
allowed-tools: "Bash(...), Read..." # Functional — configures tool access
---
```

`argument-hint` and `allowed-tools` are machine-read by the skill runner — they are not just documentation. Do not remove them or move them into the body.

### SKILL.md Body Conventions

- Use phased workflows (Phase 1, Phase 2, ...) for multi-step skills — agents follow these sequentially
- Include complete, copy-paste-ready command skeletons (full GraphQL queries with variables, bash commands with flags)
- List dependency skills with their **role** in the workflow, not just their names
- For skills that call GitHub APIs, include full parameterized GraphQL — not condensed one-liners with inline placeholders

## Quality Gates

After any substantive code changes (bash scripts, skill implementations), verify no errors:

```bash
# Bash scripts
shellcheck scripts/*.sh
bash -n scripts/*.sh   # syntax check
```

## Formatting

- 2-space indentation
- 100-column line width target
- Trim trailing whitespace, insert final newlines

## Session Completion

Work is not complete until `git push` succeeds. Before ending a session:

1. Run quality gates on changed files
2. `br sync --flush-only` if beads were modified
3. Stage, commit, and push — never leave work stranded locally

## Integration Points

Skills orchestrate these external tools:

| Tool | Purpose |
|------|---------|
| `ntm` | Tmux pane orchestration for multi-agent sessions |
| `br` | Beads CLI — dependency-aware task tracking |
| `bv` | Graph-aware triage engine (always use `--robot-*` flags) |
| Agent Mail | MCP-based async coordination between agents |
| `gh` | GitHub CLI for PR/issue operations |
