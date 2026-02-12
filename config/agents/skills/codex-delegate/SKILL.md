---
name: codex-delegate
description: |
  Delegate code review and document review tasks to OpenAI Codex CLI via `codex exec`.
  Use when:
  - The user asks to get a second opinion or review from Codex/another AI
  - The user asks to delegate a review task to Codex
  - The user explicitly asks to run codex or use codex for review
  - Code review: check implementation quality, bugs, security issues, best practices
  - Document review: check README, design docs, comments for clarity and accuracy
  Do NOT use for tasks that require file modifications (use Claude Code directly instead).
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
- `-C <path>` - Set working directory

## Code Review

Construct a prompt that specifies the target files and review criteria.

### Single file review

```bash
codex exec -s read-only "Review the implementation in src/auth.ts. Check for bugs, security issues, and adherence to best practices. Provide specific suggestions for improvement."
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

If the output is long, use `-o /tmp/codex-review.txt` and read the file afterward.

## Prompt Construction Guidelines

1. **Be specific about scope** - Name exact files or directories to review
2. **State the review criteria** - What to focus on (bugs, security, style, clarity)
3. **Request structured output** - Ask for categorized findings (e.g., by severity)
4. **Provide context** - Mention the project's language, framework, or conventions when relevant

## Notes

- `codex exec` streams progress to stderr and final output to stdout
- The command exits automatically when the agent finishes
- Requires Codex CLI to be installed and authenticated (`codex` in PATH)
- Read-only sandbox ensures Codex cannot modify any files
