# AGENTS.md

Repository-specific guidance for Codex.

## Skill Selection

- Prefer an existing skill when the task clearly matches one. Check skill metadata before recreating a workflow from scratch.
- For non-trivial work that needs planning or durable progress tracking, use the `steering` skill.
- For Git-only workflow tasks, use `git`. For GitHub operations through `gh`, use `github`.
- For cross-agent work between Codex and Claude Code, use `agent-handoff` to keep the handoff file-backed and bounded. Prefer `cc-delegate` for review-only Claude Code checks from Codex.
- Use available delegate skills for bounded research, planning, and review when they match the task. In Codex sessions, launch sub-agents only when the current user request explicitly asks for delegation or a selected skill explicitly requires a specific sub-agent for that turn; otherwise perform the equivalent checks locally.
- If the same skill-selection miss happens twice, update either this file or the affected skill `description` so the rule becomes durable.

## Cross-Agent Work

- Treat Codex as the owner for implementation, verification, and final diff quality.
- Treat Claude Code as the preferred helper for broad investigation, design alternatives, and review passes when that saves Codex tokens.
- Put handoff details under the active steering task directory, typically `~/.local/state/steering/<owner>--<repo>/<task>/handoffs/`, and send only concise pointers or summaries between agents.
- Use `agmsg` only as a local transport for short messages or handoff file paths; do not make it the source of truth.

## Autonomy

- For clear implementation requests, proceed from repository inspection to edits to verification without asking for confirmation. State minor assumptions and continue.
- Ask before proceeding only when the requested scope is ambiguous, acceptance criteria conflict, credentials or external side effects are involved, or the action is destructive.
- When several low-risk implementation choices are valid, choose the option that best matches existing repository patterns and document the choice in the final report.
- Do not stop at search-engine-style investigation when the user asked for implementation. Edit the relevant files, run the most relevant available verification, and report any verification gap.
- Treat Codex autonomy as bounded by the active sandbox and approval rules. Do not emulate Claude Code auto mode by bypassing sandboxing or approval for destructive, external, or credential-sensitive operations.

## Verification

- After changing skill metadata or discovery paths, verify with a fresh Codex session.
- Test both positive prompts and negative prompts so implicit skill matching does not become too broad.
