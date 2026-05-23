# Waza Pilot

This directory is a local-only Waza workspace for the `git` skill pilot.

The Waza config points `paths.skills` at `../config/agents/skills/`, so the
pilot reads the repository's real skill definitions directly instead of keeping
a copied or linked skill tree under `waza/skills/`.

## Source Of Truth

The primary source remains:

- `config/agents/skills/git/SKILL.md`
- `config/agents/skills/git/evals/evals.json`

This workspace is a derived execution layer for Waza. It should not become the
authoritative place for prompts or trigger intent.

## Mapping Contract

The current manual mapping from `evals.json` to Waza is:

- `skill_name` -> `config/agents/skills/<skill>/SKILL.md` via `.waza.yaml`
- `id` -> task file identity and stable case ID
- `type` -> task tags such as `positive`, `boundary`, `negative`
- `prompt` -> `inputs.prompt`
- `expected_output` -> task-specific grader expectations
- `files` -> fixture candidates when needed

Fixture-only or grader-only metadata may live only in this Waza workspace during
the pilot. If that happens, update this README with the rationale.

Current exception:

- `positive-1` adds `fixtures/change-summary.md` only in Waza, because the
  trigger prompt from `evals.json` is intentionally short and does not carry the
  change context needed to produce a concrete commit message.

## Sync Procedure

When `config/agents/skills/git/evals/evals.json` changes:

1. Update the matching task YAML under `waza/evals/git/tasks/`
2. Keep prompt text aligned exactly
3. Revisit Waza-only fixtures or grader expectations if `expected_output`
   changed materially
4. Record any drift or ambiguity in the pilot decision memo

## One-Shot Build And Run

Waza is not installed permanently in this repository. Use a temporary Nix shell
and build it from source in a temp directory:

```bash
nix shell nixpkgs#go nixpkgs#git-lfs nixpkgs#git -c bash -lc '
  set -euo pipefail
  tmp="$(mktemp -d)"
  trap "rm -rf \"$tmp\"" EXIT
  cd "$tmp"
  git clone https://github.com/microsoft/waza.git
  cd waza
  git lfs install
  git lfs pull
  go build -o waza ./cmd/waza
  cd /Users/kumewataru/dotfiles/waza
  "$tmp"/waza/waza run git -v
'
```

The current pilot uses `model: gpt-5.2-codex` in `evals/git/eval.yaml`. The
scaffolded `claude-sonnet-4.6` setting was not available in this environment,
and `waza models --json` confirmed the exact model IDs exposed by the local
Copilot SDK.

## Scope

- This pilot is local-first
- CI integration is intentionally deferred
- The goal is to learn what should later move into the `waza-eval` skill
