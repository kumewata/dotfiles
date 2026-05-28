---
name: cc-delegate
description: |
  Use when the user wants Codex to ask Claude Code for a second opinion or review on code, docs, diffs, PR changes, or design notes without modifying files. This delegates bounded review-only analysis through the Claude Code CLI (`claude -p`). Do NOT use for implementation or file edits; keep this skill review-only. Trigger especially when the user says ask Claude, ask Claude Code, cc-delegate, Claude review, second opinion from Claude, compare Codex and Claude, or review this diff/document with Claude Code.
---

# CC Delegate

Delegate review tasks from Codex to Claude Code using `claude -p` (non-interactive print mode).

## Command Pattern

```bash
claude -p --permission-mode plan --output-format text --max-turns 4 "<prompt>"
```

**Required flags:**

- `-p` / `--print` - Run Claude Code non-interactively and exit.
- `--permission-mode plan` - Keep the session in planning/review mode.

**Recommended prompt guard:**

Include this in every delegated prompt:

```text
Review only. Do not modify files, create commits, run destructive commands, or perform external side effects. Return findings with file/line references where possible.
```

**Optional flags:**

- `--model <model>` - Override model, e.g. `sonnet` or `opus`.
- `--max-turns <n>` - Raise for larger reviews; keep small for focused checks.
- `--add-dir <path>` - Allow Claude Code to inspect another directory.
- `--output-format json` - Use when scripting or preserving metadata.
- `--no-session-persistence` - Avoid saving a review-only session.

## Safety Rules

- Do not use `--dangerously-skip-permissions`, `--allow-dangerously-skip-permissions`, or `--permission-mode bypassPermissions`.
- Do not ask Claude Code to implement, patch, commit, push, install dependencies, or mutate external systems when using this skill.
- Prefer exact files, directories, or git refs in the prompt. Avoid broad "review everything" prompts unless the user asked for a broad review.
- If Claude suggests changes, Codex must inspect and implement any accepted changes itself in the current session.

## Code Review

### Git diff review

```bash
claude -p --permission-mode plan --output-format text --max-turns 4 "Review only. Do not modify files, create commits, run destructive commands, or perform external side effects. Review the current git diff for bugs, regressions, and missing tests. List findings by severity with file/line references where possible."
```

### Focused review

```bash
claude -p --permission-mode plan --output-format text --max-turns 4 "Review only. Do not modify files, create commits, run destructive commands, or perform external side effects. Review src/auth.ts specifically for authentication bypasses, token handling bugs, and unsafe error paths. List findings by severity with file/line references where possible."
```

### Multi-file review

```bash
claude -p --permission-mode plan --output-format text --max-turns 6 "Review only. Do not modify files, create commits, run destructive commands, or perform external side effects. Review the changes under src/api/ for error handling, input validation, and API consistency. List findings by severity with file/line references where possible."
```

## Document Review

```bash
claude -p --permission-mode plan --output-format text --max-turns 4 "Review only. Do not modify files, create commits, run destructive commands, or perform external side effects. Review docs/architecture.md for logical gaps, outdated claims, and unclear assumptions. Return concise findings and open questions."
```

## Execution in Codex

Run `claude -p` via the shell from the repository root unless the prompt names another directory.

If the target is outside the current repository, either run from that directory or add it explicitly:

```bash
claude -p --permission-mode plan --add-dir /path/to/other/repo --output-format text "<review prompt>"
```

If the command fails because Claude Code is not installed or authenticated, report that and continue locally unless the user asks to install or log in.

## Prompt Construction Guidelines

1. **State review-only scope** - Explicitly prohibit edits and side effects.
2. **Name the target** - Files, directories, current diff, staged diff, or base branch.
3. **State the review criteria** - Bugs, security, regressions, tests, clarity, or design risks.
4. **Request structured output** - Findings by severity, with file/line references where possible.
5. **Keep context bounded** - Delegate one coherent review question at a time.

## Notes

- Requires Claude Code CLI to be installed and authenticated (`claude` in `PATH`).
- `claude -p` prints the final response to stdout.
- Claude Code may use network-backed model access; in sandboxed Codex sessions, approval may be required before execution.
