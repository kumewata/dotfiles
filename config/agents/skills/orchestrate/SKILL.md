---
name: orchestrate
description: 複雑な機能実装・バグ修正・リファクタリング・セキュリティ対応を、planner や reviewer 系エージェントを組み合わせた段階的なオーケストレーションで進めるスキル。Claude Code のカスタムコマンド相当の流れを Codex でも再現したいときに使う。
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

## Steering Integration

orchestrate では常に `steering` スキルを使う。軽量モード判定はせず、通常モードで `requirements.md`、`design.md`、`tasklist.md` を作成する。

実行前に行うこと:

1. `steering` スキルを読む
2. Mode 1 に従って steering ディレクトリと 3 ファイルを作る
3. planner に steering ファイル更新責務を持たせる

## Execution Rules

各フェーズで必ず以下を行う:

1. 対象エージェントに元タスク、前フェーズの handoff、steering ディレクトリ位置を渡す
2. 完了後に handoff を要約して残す
3. `tasklist.md` の完了状態と completion を更新する
4. 新しいタスクや未解決事項があれば `tasklist.md` と handoff の両方に残す

handoff の最小フォーマット:

```markdown
## HANDOFF: [previous-agent] -> [next-agent]

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

最終的に以下を短くまとめて報告する:

- workflow type
- 実際の pipeline
- 各フェーズの結果
- 追加で見つかった問題
- 最終判定: `SHIP` / `NEEDS WORK` / `BLOCKED`
