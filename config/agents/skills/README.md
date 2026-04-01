# Skill Trigger Regression Matrix

This file tracks manual prompts for checking whether Codex implicitly selects the intended skill.

## How To Use

Run the prompts in a fresh Codex session without explicitly naming the skill. Record whether the expected skill was selected, whether a different skill fired, or whether no skill fired. Use the same prompts before and after editing a `description`.

## Steering

Expected skill: `steering`

Positive:

- "この変更の実装計画とタスクリストを作って"

Boundary:

- "この調査結果を作業メモとして残したい"

Negative:

- "この1行の typo を直して"

## Git

Expected skill: `git`

Positive:

- "この変更のコミットメッセージを Conventional Commits で考えて"

Boundary:

- "このブランチ戦略で rebase と merge のどちらがよい？"

Negative:

- "このPRに返信コメントを付けて"

## GitHub

Expected skill: `github`

Positive:

- "gh で PR のレビューコメントに返信したい"

Boundary:

- "この issue を親 issue に紐付ける方法を教えて"

Negative:

- "ローカルで commit を分けたい"

## Claude Config Optimizer

Expected skill: `claude-config-optimizer`

Positive:

- "CLAUDE.md と rules の整理方針を見直して"

Boundary:

- "Claude Code の changelog を見て breaking changes がないか確認して"

Negative:

- "Codex の skill description だけ直して"

## Orchestrate

Expected skill: `orchestrate`

Positive:

- "この大きめのリファクタリングを段階的に進めたい。planner と reviewer を挟んで"

Boundary:

- "このバグ修正を複数フェーズで安全に進めるならどう組む？"

Negative:

- "この単一ファイルの小さな修正をやって"

## Codex Delegate

Expected skill: `codex-delegate`

Positive:

- "この差分を Codex にレビューさせて second opinion をほしい"

Boundary:

- "README を別視点でチェックしてほしい"

Negative:

- "この設計どおりに実装して"

## Initial Naming And Split Review

- `steering`, `git`, `github`, and `codex-delegate` are scoped clearly enough after the trigger-first rewrite.
- `claude-config-optimizer` still mixes changelog analysis and config editing. If false positives remain, split it into `claude-config-optimizer` and `claude-changelog-review`.
- `orchestrate` is intentionally broad, but it should stay tied to phased execution language. If it starts stealing ordinary implementation prompts, narrow the description further or make explicit invocation the default.
