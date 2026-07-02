# Skill Trigger Regression Matrix

This file tracks manual prompts for checking whether Codex implicitly selects the intended skill.

## How To Use

Run the prompts in a fresh Codex session without explicitly naming the skill. Record whether the expected skill was selected, whether a different skill fired, or whether no skill fired. Use the same prompts before and after editing a `description`.

## Relationship To `evals/`

This file is the human-readable summary layer. Machine-readable skill evaluation assets live under `config/agents/skills/<skill>/evals/`.

- `README.md`: quick regression matrix for manual spot checks in a fresh Codex session
- `evals/evals.json`: structured prompt cases that can be validated by scripts or CI later

The two should stay aligned. When a prompt is added, removed, or reclassified here, the corresponding `evals/evals.json` should be updated in the same change when that skill has migrated.

## `evals/evals.json` Minimal Schema

Each skill-level `evals/evals.json` should follow this shape:

```json
{
  "skill_name": "steering",
  "evals": [
    {
      "id": "positive-1",
      "type": "positive",
      "prompt": "この変更の実装計画とタスクリストを作って",
      "expected_output": "Uses the steering skill and creates or updates a steering artifact.",
      "files": []
    }
  ]
}
```

Field intent:

- `skill_name`: matches the skill directory / frontmatter name
- `id`: stable case identifier within the skill
- `type`: one of `positive`, `boundary`, `negative`
- `prompt`: the user utterance used for evaluation
- `expected_output`: minimum expected behavior or trigger outcome
- `files`: optional supporting files relative to the skill directory

## Migration Status

Structured `evals/` assets currently exist for:

- `airflow`
- `steering`
- `git`
- `github`
- `orchestrate`
- `claude-config-optimizer`
- `codex-delegate`
- `cc-delegate`
- `waza-eval`
- `japanese-tech-writing`

Priority for next migration wave:

- `terraform`
- `review-assist`
- `databricks`

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
- "この設計レビューは deep-review 相当で Codex に見てもらいたい"

Negative:

- "この設計どおりに実装して"

## CC Delegate

Expected skill: `cc-delegate`

Positive:

- "この差分を Claude Code にレビューさせて second opinion をほしい"

Boundary:

- "README を Claude の視点でもチェックしてほしい"
- "この軽い docs 差分を fast-review 相当で Claude Code に見てもらって"

Negative:

- "Claude Code 向けの settings.json を整理して"

## Agent Handoff

Expected skill: `agent-handoff`

Positive:

- "Codex と Claude Code で作業を分担するための handoff を作って"

Boundary:

- "agmsg で Claude に短いレビュー依頼を送れる形にまとめて"
- "この調査は Claude、実装は Codex に分けて、balanced-review の handoff にして"

Negative:

- "この差分を Claude Code にレビューさせて second opinion をほしい"

## Airflow

Expected skill: `airflow`

Positive:

- "MWAA 用の DAG を追加したい。requirements.txt と import error も見て"

Boundary:

- "Airflow DAG の parse が遅いので top-level code をレビューして"

Negative:

- "普通の Python スクリプトの型ヒントだけレビューして"

## Waza Eval

Expected skill: `waza-eval`

Positive:

- "この skill の trigger を大きく変えたので、Waza の task と grader も整えたい"

Boundary:

- "waza run を入れる前に、fixture を足すべきケースか整理したい"

Negative:

- "Waza CLI のインストール方法を教えて"

## Japanese Tech Writing

Expected skill: `japanese-tech-writing`

Positive:

- "この変更の PR 本文を日本語で書いて"
- "この日本語の docs、LLM っぽい言い回しと冗長を削って一文一行で整えて"

Boundary:

- "Write the PR description for this change in English"

Negative:

- "この関数のバグを直して"

Note: `japanese-tech-writing`（客観的な文章規範）と `tone`（個人の文体再現）は責務が異なり併用できる。日本語 PR 本文では両方が同時に該当しうるため、規範適用が漏れていないかをこの matrix で確認する。

## Initial Naming And Split Review

- `steering`, `git`, `github`, and `codex-delegate` are scoped clearly enough after the trigger-first rewrite.
- `claude-config-optimizer` still mixes changelog analysis and config editing. If false positives remain, split it into `claude-config-optimizer` and `claude-changelog-review`.
- `orchestrate` is intentionally broad, but it should stay tied to phased execution language. If it starts stealing ordinary implementation prompts, narrow the description further or make explicit invocation the default.
