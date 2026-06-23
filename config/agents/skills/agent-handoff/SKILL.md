---
name: agent-handoff
description: Use when coordinating bounded work between Codex, Claude Code, or another coding agent; preparing a handoff brief; reducing Codex token usage by delegating research, planning, or review; or using agmsg as a transport for short cross-agent messages. Keep the skill focused on handoff contracts and do not use it for implementation by itself.
---

# Agent Handoff

Use this skill to prepare compact, file-backed handoffs between coding agents. The goal is to keep each agent's context bounded: put durable details in a handoff file under the active steering task, then send only a short pointer through chat, `cc-delegate`, `codex-delegate`, or `agmsg`.

## Role Split

- Codex owns implementation, verification, final diff quality, and changes that must respect the active sandbox and repository `AGENTS.md`.
- Claude Code owns broad investigation, design alternatives, review passes, and second opinions when that saves Codex tokens.
- The receiving agent may recommend changes, but the current primary agent must inspect and decide what to apply.
- Use `cc-delegate` from Codex for review-only Claude Code checks. Use `codex-delegate` from Claude Code for review-only Codex checks.
- Use `agmsg` only as a transport for concise messages or file pointers, not as the source of truth.

## Handoff Workflow

1. Decide the receiver role: `research`, `plan`, `review`, or `implementation`.
2. Choose a budget profile: `fast-review`, `balanced-review`, `deep-review`, or `security-review`.
3. Create or update a handoff file under the active steering task directory's `handoffs/` subdirectory when the details exceed a few lines. Use a path like `~/.local/state/steering/<owner>--<repo>/<task>/handoffs/<handoff-name>.md`.
4. Keep the message to the other agent under roughly 10 lines and include the handoff path.
5. Tell the receiver whether file edits are allowed. Default to review-only unless implementation is explicitly requested.
6. Ask for bounded output: findings, recommended plan, patch summary, or verification result.
7. After receiving the response, summarize what was accepted, what was rejected, and what remains.

## Budget Profiles

| Profile           | Use for                                                               | Escalate when                                                  |
| ----------------- | --------------------------------------------------------------------- | -------------------------------------------------------------- |
| `fast-review`     | Typos, docs clarity, tiny diffs, obvious missing tests                | The result affects production behavior or security             |
| `balanced-review` | Normal reviews, focused bug risk checks, API consistency              | The change spans many files or has unclear architecture impact |
| `deep-review`     | Broad design review, tricky debugging, multi-file regressions         | Security, data deletion, billing, or permission risks appear   |
| `security-review` | Auth, permissions, secrets, data loss, billing, external side effects | Do not downgrade silently                                      |

Use these profile names in the handoff. Let `cc-delegate` or `codex-delegate` translate the profile into the local model and reasoning flags.

## Handoff Template

```md
# <task-name> handoff

## Goal

<What should be achieved?>

## Current State

- Repo:
- Branch:
- Relevant files:
- Current diff or artifact:

## Constraints

- Do not:
- Must preserve:
- Verification expected:

## Requested Role

research | plan | review | implementation

## Model / Budget Hint

fast-review | balanced-review | deep-review | security-review

## Request

<Specific bounded request for the receiving agent.>

## Output Contract

- Return at most:
- Include file/line references when possible:
- Do not modify files unless explicitly allowed:

## Result Log

- <timestamp>: <agent/result summary>
```

## Message Patterns

For review-only delegation:

```text
Review only. Do not modify files, create commits, run destructive commands, or perform external side effects.
Profile: balanced-review.
Read <steering-task-dir>/handoffs/<handoff-name>.md and return findings by severity with file/line references where possible.
```

For implementation delegation:

```text
Read <steering-task-dir>/handoffs/<handoff-name>.md.
Profile: balanced-review.
Implement only the requested minimal change, run the listed verification, and return a diff summary plus test result.
```

For `agmsg` transport:

```text
@<agent-name> Read <steering-task-dir>/handoffs/<handoff-name>.md. Requested role: review. Profile: fast-review. Return concise findings only.
```

## Token Discipline

- Prefer paths, line numbers, command outputs, and summaries over pasted logs.
- Do not pass full files when `rg`, `git diff`, or a focused excerpt is enough.
- Split large tasks into a research handoff followed by an implementation handoff.
- Record conclusions in the handoff file so future turns do not need to reload conversation history.
