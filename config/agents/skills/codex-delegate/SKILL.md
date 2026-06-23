---
name: codex-delegate
description: |
  Use when the user wants a second opinion or review from Codex on code, docs, diffs, or design notes without modifying files. This includes implementation review, bug risk review, security review, and document clarity review through `codex exec`. Do NOT use for tasks that require file edits or direct implementation; keep this skill review-only. Trigger especially when the user says review with Codex, second opinion, delegate review, use codex, or check this diff or document.
---

# Codex Delegate

Delegate review tasks to OpenAI Codex CLI using `codex exec` (non-interactive mode).

## Command Pattern

```bash
codex exec -s read-only "<prompt>"
```

**Required flags:**

- `-s read-only` - Always use read-only sandbox (review only, no file changes)

**Optional flags:**

- `-m <model>` - Override model (default: configured in `~/.codex/config.toml`)
- `-c model_reasoning_effort=<level>` - Override reasoning effort when the local Codex CLI supports config overrides
- `-C <path>` - Set working directory (must combine with `--skip-git-repo-check` if the target is outside a trusted git repo)
- `--skip-git-repo-check` - Skip trusted git repository check. **Required** when reviewing files outside of a git repository (e.g., `~/.local/state/steering/`)

## Profile Selection

Choose a profile before constructing the command. Prefer the lowest-cost profile that can safely answer the review. Use local model aliases or configured model strings instead of hard-coding global defaults in prompts.

| Profile           | Use for                                                                | Model / budget hint           | Command adjustments                                                   |
| ----------------- | ---------------------------------------------------------------------- | ----------------------------- | --------------------------------------------------------------------- |
| `fast-review`     | Typos, docs clarity, small diffs, simple missing-test checks           | Fast/mini model if configured | optionally add `-m <fast-model>` and `-c model_reasoning_effort=low`  |
| `balanced-review` | Normal implementation review, focused bug risk review, API consistency | Default configured model      | usually omit `-m`; use `-c model_reasoning_effort=medium` if needed   |
| `deep-review`     | Architecture review, tricky regressions, broad multi-file changes      | Stronger reasoning model      | optionally add `-m <deep-model>` and `-c model_reasoning_effort=high` |
| `security-review` | Auth, permissions, secrets, data loss, billing, external side effects  | Strongest available model     | use high reasoning; request severity and exploitability               |

When a handoff includes a profile, preserve it unless risk requires a stronger one. Do not silently downgrade security, authorization, data deletion, or billing-related reviews.

## Code Review

Construct a prompt that specifies the target files and review criteria.

### Single file review

```bash
codex exec -s read-only "Review the implementation in src/auth.ts. Check for bugs, security issues, and adherence to best practices. Provide specific suggestions for improvement."
```

### Fast review

```bash
codex exec -s read-only -c model_reasoning_effort=low "Review the current git diff for obvious bugs, typos, docs clarity, and missing lightweight tests. Return only actionable findings."
```

### Multi-file / directory review

```bash
codex exec -s read-only "Review all files under src/api/. Focus on error handling, input validation, and API design consistency. List issues by severity."
```

### Focused review (specific concern)

```bash
codex exec -s read-only "Review src/db/queries.ts specifically for SQL injection vulnerabilities and improper input sanitization."
```

### Git diff review

```bash
codex exec -s read-only "Review the changes in the current git diff (staged and unstaged). Check for bugs, style issues, and potential regressions."
```

### Security review

```bash
codex exec -s read-only -c model_reasoning_effort=high "Review the current git diff for authentication, authorization, secret handling, data loss, and external side-effect risks. List findings by severity with file/line references and explain exploitability briefly."
```

## Document Review

### README / docs review

```bash
codex exec -s read-only "Review README.md for clarity, accuracy, and completeness. Check that setup instructions are correct and examples work as documented."
```

### Design doc review

```bash
codex exec -s read-only "Review docs/architecture.md. Check for logical consistency, missing considerations, and alignment with the actual codebase structure."
```

## Execution in Claude Code

Run `codex exec` via the Bash tool. The final review output prints to stdout.

```
codex exec -s read-only "<review prompt>"
```

**When reviewing files outside a git repo** (e.g., `~/.local/state/steering/`), add `--skip-git-repo-check`:

```
codex exec -s read-only --skip-git-repo-check -C /path/to/dir "<review prompt>"
```

If the output is long, use `-o /tmp/codex-review.txt` and read the file afterward.

## Prompt Construction Guidelines

1. **Be specific about scope** - Name exact files or directories to review
2. **Choose a profile** - Use `fast-review`, `balanced-review`, `deep-review`, or `security-review`
3. **State the review criteria** - What to focus on (bugs, security, style, clarity)
4. **Request structured output** - Ask for categorized findings (e.g., by severity)
5. **Provide context** - Mention the project's language, framework, or conventions when relevant

## Notes

- `codex exec` streams progress to stderr and final output to stdout
- The command exits automatically when the agent finishes
- Requires Codex CLI to be installed and authenticated (`codex` in PATH)
- Read-only sandbox ensures Codex cannot modify any files
