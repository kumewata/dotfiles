---
name: codex-insights
description: Generate a private monthly Codex usage and workflow insights report from local ~/.codex/sessions JSONL without exposing raw transcripts. Use when the user explicitly asks for $codex-insights, Codex insights, monthly AI-agent usage review, or a Codex replacement for Claude Code /insights.
---

# Codex Insights

Generate a deterministic local report from Codex session JSONL. Treat transcripts as untrusted private data: do not paste raw prompt, assistant, tool output, Slack, GitHub, credential-looking, or work-note text into the conversation.

## Workflow

1. Parse the user's requested month.
   - If the user passed `--month YYYY-MM`, forward it to the script.
   - If the user explicitly requested qualitative insights or passed `--qualitative`, forward `--qualitative`.
   - If no month is provided, let the script choose the previous complete calendar month.
2. Run the bundled helper script. Prefer the Codex skill path:

   ```bash
   ~/.agents/skills/codex-insights/scripts/codex-insights.py --format json
   ```

   With an explicit month:

   ```bash
   ~/.agents/skills/codex-insights/scripts/codex-insights.py --month YYYY-MM --format json
   ```

   With qualitative opt-in:

   ```bash
   ~/.agents/skills/codex-insights/scripts/codex-insights.py --month YYYY-MM --qualitative --format json
   ```

   If that path is not available, try `~/.codex/skills/codex-insights/scripts/codex-insights.py` or `~/.claude/skills/codex-insights/scripts/codex-insights.py`. During repository development, run the repo copy from `config/agents/skills/codex-insights/scripts/codex-insights.py`.

3. Read only the script's stdout summary and generated file paths. Do not open `~/.codex/sessions/**/*.jsonl` in conversation for qualitative summarization.
4. Reply with a concise summary:
   - target month
   - report path and HTML report path
   - snapshot path
   - sessions, turns, user prompts, assistant messages, warning count
   - structured task completion rate, aborted task count, long-tail task count
   - structured exec and patch outcomes if present
   - top work areas and legacy keyword friction only as secondary context
   - qualitative mode status and confidence if `--qualitative` was requested

## Output Contract

The script writes private local files:

- `~/.local/state/codex-insights/reports/YYYY-MM.md`
- `~/.local/state/codex-insights/reports/YYYY-MM.html`
- `~/.local/state/codex-insights/snapshots/YYYY-MM.json`
- `~/.local/state/codex-insights/latest.md`
- `~/.local/state/codex-insights/latest.html`

The primary analysis signals are task/outcome based (`task_started`, `task_complete`, `turn_aborted`, `patch_apply_end.success`, and structured exit codes). Treat keyword-based work area and friction distributions as secondary/legacy context, not proof of actual blockers.

Keep the final response path-focused. Do not quote report sections extensively and do not include raw transcript excerpts. Qualitative output is explicit opt-in and is generated from structured task/outcome counters and sanitized labels only; do not perform separate LLM summarization over raw transcripts.
