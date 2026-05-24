---
name: waza-eval
description: |
  Use when creating a new skill or making a substantial change to an existing skill and you also need to design, update, or review Waza-based executable evaluations. This includes deciding whether Waza is warranted, mapping `evals.json` cases into Waza tasks, choosing fixtures and graders, selecting a valid model with `waza models --json`, and running a local-first `waza run` workflow. Do NOT use for installing the Waza CLI itself or for general skill-authoring advice that does not involve Waza; use `skill-creator` for skill design and this skill for the Waza execution layer. Trigger especially when the user mentions Waza, `waza run`, `waza models`, executable evals, compare, graders, fixtures, or wants to validate a skill change with model-backed evaluation.
---

# Waza Eval

Guide for adding or updating Waza-based executable evals for skills.

## Scope

`waza-eval` owns the execution layer:

- whether Waza should be added for a skill change
- how `evals.json` maps to Waza tasks
- when to add Waza-only fixtures
- how to choose simple graders first
- how to run the eval locally

It does not own:

- skill design in general
- description tuning in general
- Waza CLI installation

Use `skill-creator` for the skill itself. Use `waza-eval` when the question becomes "how do we make this executable in Waza?"

## Preconditions

- `waza` CLI is already installed and available in `PATH`
- the skill has a directory under `config/agents/skills/<skill>/`
- `config/agents/skills/<skill>/evals/evals.json` exists, or should be created as the source of truth

If `waza` is not in `PATH`, stop treating this as a `waza-eval` task and resolve the environment first.

## Source Of Truth

Treat `config/agents/skills/<skill>/evals/evals.json` as the source layer.

Treat Waza files as the execution layer.

Keep this contract:

- `skill_name` matches the skill directory and Waza eval target
- `id` becomes the stable task identity
- `type` becomes task tags such as `positive`, `boundary`, `negative`
- `prompt` stays aligned exactly unless there is a deliberate reason to diverge
- `expected_output` informs grader design
- `files` carries supporting files when they are part of the source eval case

Waza-only fixtures are allowed when the prompt is intentionally short for trigger testing but not rich enough to produce a concrete output. Record that exception in the Waza README or pilot memo.

## When To Add Waza

Waza is a good fit when:

- a new skill is being added and you want model-backed validation
- a skill description or trigger behavior changed materially
- `evals.json` was added or substantially revised
- you want to confirm trigger, anti-trigger, or boundary behavior with a real model
- you are considering later CI adoption and want a local-first pilot first

Waza is usually not the first move when:

- the change is a tiny typo or formatting-only edit
- the skill has no meaningful `evals.json` cases yet
- you are still deciding the basic skill shape and do not have stable cases

## Workflow

1. Read `config/agents/skills/<skill>/evals/evals.json`.
2. Decide which cases should become Waza tasks first. Prefer one `positive` and one `negative`. Add `boundary` once the first pass works.
3. Check whether the prompt alone is enough to produce a meaningful output.
4. If not, add the minimum Waza-only fixture needed to make the task executable. Do not rewrite the source prompt just to make execution easier.
5. Start with text or regex-style graders. Keep them narrow and legible.
6. Run `waza models --json` and choose an actual available model ID. Do not trust scaffold defaults blindly.
7. Run `waza run <skill> -v` locally.
8. Inspect failures in this order:
   - wrong model or unavailable model
   - bad fixture assumptions
   - brittle grader
   - genuine trigger mismatch
9. Only after stable local runs should you discuss compare, behavior graders, or CI integration.

## Model Selection

Always discover the real model IDs first:

```bash
waza models --json
```

Then set the Waza eval config to an actual available ID such as `gpt-5.2-codex`.

Do not use broad labels like `gpt-5` unless the local environment explicitly exposes that exact ID.

## Grader Strategy

First pass:

- text contains / not-contains checks
- regex checks for structured outputs
- small, readable assertions tied to the eval intent

Later passes:

- token budget
- behavior graders
- compare flows

Do not let cost or token-budget checks dominate before the task itself is known-good. If a grader keeps failing while the trigger behavior looks right, simplify the grader first.

## Fixture Strategy

Use Waza-only fixtures sparingly.

Good reasons:

- commit-message prompts that need a change summary or diff
- file-generation prompts that need a tiny sample input
- anti-trigger checks that need contextual files to avoid ambiguity

Bad reasons:

- hiding that the source prompt is unclear
- compensating for a weak skill description
- adding large context blobs "just in case"

## Verification Checklist

Before calling the Waza update done, verify:

- `evals.json` and Waza task files still align
- the chosen model exists in `waza models --json`
- at least one positive and one negative case run locally
- any Waza-only fixture has a short rationale written down
- the graders are readable enough that another person can understand why a task passed or failed

## Anti-Patterns

- updating Waza tasks without updating `evals.json`
- guessing model names
- forcing prompt-only execution when a tiny fixture is clearly needed
- adding token-budget or compare logic too early
- discussing CI before a local run is stable
- using this skill for CLI installation work

## Example Commands

Inspect models:

```bash
waza models --json
```

Run one skill locally:

```bash
cd waza
waza run git -v
```

## Handoff Notes

If the work finishes with a useful pattern, leave behind:

- updated `evals.json`
- Waza task and fixture files
- a short note explaining any Waza-only fixture
- the chosen model ID
- whether the next step is `continue`, `stop`, or `needs redesign`
