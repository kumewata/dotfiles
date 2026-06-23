# Omnigent Experiments

This directory contains local experiments for running multiple coding agents
through Omnigent. Keep these configs experimental until the workflow is proven
against real tasks.

## Current Experiment

`agents/codex-primary-claude-research/` tests this operating model:

- Codex is the primary owner for task management, integration, verification,
  and the final user-facing result.
- Claude Code is a secondary lane for bounded `research` and `review-only`
  work.
- There is exactly one primary owner for the task flow.
- Findings from Claude are advisory. Codex decides what to apply.

## One-time Setup

Omnigent is not installed by this dotfiles repo yet. Install it with one of the
official routes:

```bash
uv tool install omnigent
```

Then confirm the required CLIs are available:

```bash
omni --version
command -v codex
command -v claude
command -v tmux
```

Run Omnigent setup if credentials or defaults are missing:

```bash
omni setup
```

Initial local result on 2026-06-23:

- `uv tool install omnigent` installed Omnigent `0.2.0`.
- `omni --version` returned `omnigent 0.2.0`.
- `codex`, `claude`, and `tmux` were all present.
- In the Codex sandbox, `omni run ...` needs approval because Omnigent writes
  `~/.omnigent` logs and binds a local server on `127.0.0.1`.
- With approval, the local server reached `/health 200`, but the headless runner
  did not become ready before the CLI timeout. Run `omni setup` and retry from a
  normal terminal before treating this experiment as operational.

First successful run on 2026-06-23 (normal terminal):

- Credentials were already configured (`omni config list` shows Claude and Codex
  subscription credentials, both default), so `omni setup` was not needed again.
- `omni run` is a TUI that needs a real TTY. Driving it from a non-interactive
  shell required wrapping it in a detached `tmux` session; the local server,
  runner, and `codex` harness all came up and a turn completed normally — the
  headless-runner stall seen in the Codex sandbox did not reproduce.
- The read-only task ("inspect AGENTS.md and summarize when to delegate to
  Claude") was handled directly by Codex without dispatching `claude_research`,
  which is the intended behavior for a trivial read task (delegate only to reduce
  context or risk). No files were edited.
- `omni run` from the repo checkout creates an ephemeral Codex HOME at
  `.codex-tmp/` in the cwd; it is now gitignored. Stop background processes with
  `omni stop` after a run.

Open follow-up: exercise a task large enough to actually trigger a
`claude_research` delegation, to validate the secondary-lane prompt and the
findings-vs-decision separation in the response.

## Trial Run

After applying Home Manager:

```bash
nix run --impure .#switch
omni run ~/.config/omnigent/agents/codex-primary-claude-research \
  -p "In /Users/wataru.kume/dotfiles, inspect AGENTS.md and summarize when to delegate to Claude. Do not edit files."
```

From the repository checkout, the same config can be run directly:

```bash
omni run config/omnigent/agents/codex-primary-claude-research \
  -p "Inspect AGENTS.md and summarize when to delegate to Claude. Do not edit files."
```

## Evaluation

Use a small read-only task first. The run is useful only if:

- Codex remains the only primary owner in the final answer.
- Claude Code is used only for research or review unless explicitly reassigned.
- The response identifies what came from Claude and what Codex accepted.
- No files are edited during a read-only task.
- The workflow feels cheaper or clearer than calling `claude -p` manually.

If those checks pass, the next step is to promote the useful parts into the
`agent-handoff` skill or add a dedicated Omnigent skill.
