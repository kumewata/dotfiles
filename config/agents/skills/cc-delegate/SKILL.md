---
name: cc-delegate
description: |
  Use when the user wants Codex to ask Claude Code for a second opinion or review on code, docs, diffs, PR changes, or design notes without modifying files. This delegates bounded review-only analysis through the Claude Code CLI (`claude -p`). Do NOT use for implementation or file edits; keep this skill review-only. Trigger especially when the user says ask Claude, ask Claude Code, cc-delegate, Claude review, second opinion from Claude, compare Codex and Claude, or review this diff/document with Claude Code.
---

# CC Delegate

Delegate review tasks from Codex to Claude Code using `claude -p` (non-interactive print mode).

## Command Pattern

```bash
claude -p --permission-mode plan --output-format text "<prompt>"
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

- `--model <model>` - Override model when a local Claude Code alias or model string is available.
- `--effort <level>` - Set reasoning effort (`low`, `medium`, `high`, `xhigh`, or `max`) when useful.
- `--max-budget-usd <amount>` - Cap API spend for print-mode delegation when a hard budget is useful.
- `--add-dir <path>` - Allow Claude Code to inspect another directory.
- `--output-format json` - Use when scripting or preserving metadata.
- `--no-session-persistence` - Avoid saving a review-only session.

## Profile Selection

Choose a profile before constructing the command. Prefer the cheapest profile that can answer the review safely. If a named model alias is unavailable in the local Claude Code setup, omit `--model` and keep the profile's scope, `--effort`, and output-bounding guidance.

| Profile           | Use for                                                              | Model / budget hint       | Command adjustments                                                            |
| ----------------- | -------------------------------------------------------------------- | ------------------------- | ------------------------------------------------------------------------------ |
| `fast-review`     | Typos, docs clarity, tiny diffs, simple test gaps                    | Fast/low-cost model       | use `--effort low`; add a fast model alias or `--max-budget-usd` if configured |
| `balanced-review` | Normal diff review, focused bug risk review, API consistency         | Default balanced model    | use `--effort medium`; usually omit `--model`                                  |
| `deep-review`     | Broad design review, tricky debugging, multi-file regressions        | Strong reasoning model    | use `--effort high`; use a stronger model alias if configured                  |
| `security-review` | Auth, permissions, data loss, secret handling, external side effects | Strongest available model | use `--effort high` or stronger; ask for severity and exploitability           |

When the user supplies a profile through `agent-handoff`, preserve it unless the risk clearly demands a stronger review. Do not silently downgrade security, authorization, data deletion, or billing-related reviews.

## Safety Rules

- Do not use `--dangerously-skip-permissions`, `--allow-dangerously-skip-permissions`, or `--permission-mode bypassPermissions`.
- Do not ask Claude Code to implement, patch, commit, push, install dependencies, or mutate external systems when using this skill.
- Prefer exact files, directories, or git refs in the prompt. Avoid broad "review everything" prompts unless the user asked for a broad review.
- If Claude suggests changes, Codex must inspect and implement any accepted changes itself in the current session.

## Code Review

### Git diff review

```bash
claude -p --permission-mode plan --output-format text --effort medium "Review only. Do not modify files, create commits, run destructive commands, or perform external side effects. Review the current git diff for bugs, regressions, and missing tests. List findings by severity with file/line references where possible."
```

### Fast review

```bash
claude -p --permission-mode plan --output-format text --effort low "Review only. Do not modify files, create commits, run destructive commands, or perform external side effects. Review the current git diff for obvious bugs, typos, docs clarity, and missing lightweight tests. Return only actionable findings."
```

### Focused review

```bash
claude -p --permission-mode plan --output-format text --effort medium "Review only. Do not modify files, create commits, run destructive commands, or perform external side effects. Review src/auth.ts specifically for authentication bypasses, token handling bugs, and unsafe error paths. List findings by severity with file/line references where possible."
```

### Multi-file review

```bash
claude -p --permission-mode plan --output-format text --effort high "Review only. Do not modify files, create commits, run destructive commands, or perform external side effects. Review the changes under src/api/ for error handling, input validation, and API consistency. List findings by severity with file/line references where possible."
```

### Security review

```bash
claude -p --permission-mode plan --output-format text --effort high "Review only. Do not modify files, create commits, run destructive commands, or perform external side effects. Review the current git diff for authentication, authorization, secret handling, data loss, and external side-effect risks. List findings by severity with file/line references and explain exploitability briefly."
```

## Document Review

```bash
claude -p --permission-mode plan --output-format text --effort medium "Review only. Do not modify files, create commits, run destructive commands, or perform external side effects. Review docs/architecture.md for logical gaps, outdated claims, and unclear assumptions. Return concise findings and open questions."
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
3. **Choose a profile** - Use `fast-review`, `balanced-review`, `deep-review`, or `security-review`.
4. **State the review criteria** - Bugs, security, regressions, tests, clarity, or design risks.
5. **Request structured output** - Findings by severity, with file/line references where possible.
6. **Keep context bounded** - Delegate one coherent review question at a time.

## Notes

- Requires Claude Code CLI to be installed and authenticated (`claude` in `PATH`).
- `claude -p` prints the final response to stdout.
- Claude Code may use network-backed model access; in sandboxed Codex sessions, approval may be required before execution.
