---
name: orchestrate
description: Use when the user wants a complex implementation, bug fix, refactor, or security-sensitive change to be handled in multiple explicit phases with planning, review, and handoff artifacts instead of one straight-line execution. Do NOT use for simple fixes, single-file edits, or tasks that do not need staged review. Trigger especially when the user asks for orchestration, phased execution, planner plus reviewer flow, multi-agent workflow, or asks to use orchestrate.
---

# Orchestrate Skill

複雑なタスクを単一エージェントで一気に進めず、計画、実装、レビュー、クロスチェックを段階的に進める。

## 使うタイミング

- 複数フェーズに分けたほうが安全な機能実装
- 変更範囲が広いバグ修正
- リファクタリングと回帰確認を伴う変更
- セキュリティ観点を明示的に挟みたい変更

単一ファイルの自明な修正には使わない。

## Workflow Type

以下のいずれかを最初に決める。未指定なら `feature` として扱う。

- `feature`
- `bugfix`
- `refactor`
- `security`
- `custom`

## Agent Pipeline

標準パイプライン:

```text
feature:  planner → tdd-guide → code-reviewer → security-reviewer → codex-review
bugfix:   planner → tdd-guide → code-reviewer → codex-review
refactor: planner → architect → code-reviewer → tdd-guide → codex-review
security: planner → security-reviewer → code-reviewer → codex-review
custom:   [user-specified agents] → codex-review
```

追加エージェントが必要なら `codex-review` の直前に挿入する。

## Phase Strictness

標準 pipeline は維持するが、各 workflow の phase は次の 3 区分で扱う。

- `required`: 原則 skip 不可。skip するなら強い技術的理由を残す
- `conditionally skippable`: 条件を満たすときだけ skip 可。理由と残留リスクを残す
- `optional`: 実行してもよいが必須ではない

workflow ごとの基準:

- `feature`
  - `planner`: `required`
  - `tdd-guide`: `conditionally skippable`
  - skip 条件: テスト戦略が既存で自明、または設定変更中心で追加の test design 価値が低い
  - `code-reviewer`: `required`
  - `security-reviewer`: `conditionally skippable`
  - skip 条件: 変更がローカル設定や非機密 UI 調整に閉じ、セキュリティ境界に触れない
  - `codex-review`: `required`
- `bugfix`
  - `planner`: `required`
  - `tdd-guide`: `conditionally skippable`
  - skip 条件: 再現手順と修正方針が単純で、追加テスト観点が既存 review に吸収される
  - `code-reviewer`: `required`
  - `codex-review`: `required`
- `refactor`
  - `planner`: `required`
  - `architect`: `conditionally skippable`
  - skip 条件: 構造変更が局所的で、設計選択が既存方針に完全従属する
  - `code-reviewer`: `required`
  - `tdd-guide`: `conditionally skippable`
  - skip 条件: 振る舞い不変で、既存テスト維持のみで十分と説明できる
  - `codex-review`: `required`
- `security`
  - `planner`: `required`
  - `security-reviewer`: `required`
  - `code-reviewer`: `required`
  - `codex-review`: `required`
- `custom`
  - user-specified phases: `conditionally skippable`
  - `codex-review`: `required`
  - planner を外す場合は custom pipeline を最初に明示する

## Steering Integration

orchestrate では常に `steering` スキルを使う。軽量モード判定はせず、通常モードで `requirements.md`、`design.md`、`tasklist.md` を作成する。

実行前に行うこと:

1. `steering` スキルを読む
2. Mode 1 に従って steering ディレクトリと 3 ファイルを作る
3. planner に steering ファイル更新責務を持たせる

## Execution Rules

各フェーズで必ず以下を行う:

1. 対象エージェントに元タスク、前フェーズの handoff path、steering ディレクトリ位置を渡す
2. 完了後に steering 配下へ handoff ファイルを保存する
3. `tasklist.md` の完了状態と completion を更新する
4. 新しいタスクや未解決事項があれば `tasklist.md` と handoff の両方に残す

handoff 保存規約:

- 保存先は steering ディレクトリ直下
- ファイル名は `handoff-<phase>.md` を基本とする
  - 例: `handoff-planner.md`
  - 例: `handoff-tdd-guide.md`
  - 例: `handoff-code-reviewer.md`
- 同一 phase を再実行する場合や cross-session 継続で上書きを避けたい場合は、`handoff-<phase>-<timestamp>.md` を使ってよい
- 次 phase には、直前 handoff の本文要約ではなく handoff path を必ず渡す
- cross-session で再開する場合は、既存 handoff 群を読み直し、次 phase の入力に使う
- phase を skip した場合は、handoff に skip 情報を残す
  - `Skipped Phase`
  - `Skip Reason`
  - `Why this is acceptable for this workflow`
  - `Residual Risks`
- 判定語彙は次で固定する
  - `not observed`: 記録不足または観測不足
  - `skipped with reason`: skip 理由が handoff / final report に残っている
  - `required phase skipped`: `required` phase を skip しており、要注意

handoff の最小フォーマット:

```markdown
## HANDOFF: [completed-phase] -> [next-phase]

### Context

[Summary of work completed]

### Findings

[Key decisions and discoveries]

### Files Modified

[Touched files]

### Open Questions

[Unresolved items]

### Recommendations

[Next actions]
```

## Tool Mapping

実行環境に応じて同じ意図を次のツールに読み替える。

- Claude Code: Agent tool / Skill tool
- Codex: `spawn_agent`, `wait_agent`, `send_input`

Codex では次の原則で進める:

1. 直近のクリティカルパスは自分で進め、独立した sidecar タスクだけを sub-agent に渡す
2. 各 sub-agent には明確な責務と成果物を指定する
3. 競合しそうなファイルを複数 worker に同時編集させない
4. `wait_agent` は必要な結果が次の手順をブロックするときだけ使う

## Codex Review Phase

最後に、全体差分と各エージェントの指摘を統合して Codex 視点のレビューを行う。Codex 上で実行している場合は追加の `codex exec` を必須にしない。現在のセッションで以下を明示してレビューすればよい。

- 元タスク
- `git diff --staged` と `git diff` の要約
- 各エージェントの所見
- 未解決事項

レビュー観点:

1. 他エージェントが見落とした問題はないか
2. 指摘同士の矛盾や重複はないか
3. 全体評価は `SHIP` / `NEEDS WORK` / `BLOCKED` のどれか

外部の Codex CLI レビューが使えない場合でもオーケストレーション自体は失敗扱いにしない。

## Finalization

最終報告の前後で steering を必ず更新する。

1. `tasklist.md` の未完了タスクを確認する
2. 完了済みなら status を `completed`、completion を `100%` にする
3. `requirements.md` の受け入れ条件を更新する
4. 振り返り、残課題、次アクションを追記する

## Output

最終報告は次の固定テンプレートに従う:

```markdown
# Orchestration Report

## Workflow Type

[feature | bugfix | refactor | security | custom]

## Actual Pipeline

[planner -> ... -> codex-review]

## Phase Results

- [phase-name]: COMPLETE | SKIPPED (reason) | FAILED (reason)
- [phase-name]: COMPLETE | SKIPPED (reason) | FAILED (reason)

## Issues Found

- [cross-phase issue or notable finding]
- [remaining risk or "none"]

## Final Verdict

SHIP | NEEDS WORK | BLOCKED
```

必須ルール:

- `Workflow Type`, `Actual Pipeline`, `Phase Results`, `Issues Found`, `Final Verdict` を必ず含める
- `Final Verdict` は `SHIP` / `NEEDS WORK` / `BLOCKED` のいずれかを明示する
- `codex-review` を skip した場合は `Phase Results` と `Issues Found` の両方に理由を残す
- workflow 固有 phase を skip した場合も同様に理由を残す
- `required` phase を skip した場合は、`required phase skipped` と分かる書き方にする
