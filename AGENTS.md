# AGENTS.md

Repository-specific guidance for Codex.

## Skill Selection

- Prefer an existing skill when the task clearly matches one. Check skill metadata before recreating a workflow from scratch.
- For non-trivial work that needs planning or durable progress tracking, use the `steering` skill.
- For Git-only workflow tasks, use `git`. For GitHub operations through `gh`, use `github`.
- If the same skill-selection miss happens twice, update either this file or the affected skill `description` so the rule becomes durable.

## Verification

- After changing skill metadata or discovery paths, verify with a fresh Codex session.
- Test both positive prompts and negative prompts so implicit skill matching does not become too broad.
