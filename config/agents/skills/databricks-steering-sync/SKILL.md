---
name: databricks-steering-sync
description: |
  Databricks Workspace とローカルの steering ドキュメントを同期する。
  push（ローカル → Databricks）と pull（Databricks → ローカル）の両方向に対応。
  pull 時は diff を解釈してローカルファイルにマージする。
  Use when:
  - steering ドキュメントを Databricks Genie Code に同期したいとき
  - Databricks 上の変更をローカルに取り込みたいとき
  - ユーザーが「databricks に同期」「Genie に push」「pull して」と言ったとき
---

# Databricks Steering Sync

ローカルの steering ドキュメント（`~/.local/state/steering/`）を Databricks Workspace に同期する。

## 前提

- `databricks` CLI がインストール済みで認証が完了していること
- スクリプト: `~/.claude/scripts/sync-to-genie.sh`

## Push（ローカル → Databricks）

ローカルの steering ドキュメントを Databricks Workspace にアップロードする。

```bash
# 差分同期（デフォルト）
~/.claude/scripts/sync-to-genie.sh <steering-dir>

# 完全同期（リモート側で削除されたファイルもローカルの削除を反映する）
~/.claude/scripts/sync-to-genie.sh --full <steering-dir>

# dry-run（実際にはアップロードしない）
~/.claude/scripts/sync-to-genie.sh --dry-run <steering-dir>
```

`<steering-dir>` は `~/.local/state/steering/<owner--repo>/<task-dir>/` 形式。

## Pull（Databricks → ローカル）

Databricks Workspace の変更をローカルに取り込む。

### 手順1: diff を確認

```bash
~/.claude/scripts/sync-to-genie.sh --pull <steering-dir>
```

unified diff が stdout に出力される。差分がなければ「No differences」と報告される。

### 手順2: diff を解釈してマージ

diff 出力を解析し、以下のマージ戦略に従う:

- **ローカルのみ変更あり**: ローカルを保持（何もしない）
- **リモートのみ変更あり**: リモートの変更を Edit ツールでローカルに反映
- **両方に変更あり**: セクション単位でマージ。競合箇所はユーザーに確認

### 手順3: マージ後に push で同期を確定

```bash
~/.claude/scripts/sync-to-genie.sh <steering-dir>
```

### Pull（強制上書き）

リモートが正しいとわかっている場合:

```bash
~/.claude/scripts/sync-to-genie.sh --pull --force <steering-dir>
```

バックアップが `<steering-dir>.bak.<timestamp>` に自動作成される。

### Pull（dry-run）

リモートのファイル一覧のみ確認:

```bash
~/.claude/scripts/sync-to-genie.sh --pull --dry-run <steering-dir>
```

## SKILL.md の初期配置

Genie Code 用の SKILL.md を Databricks Workspace にデプロイする:

```bash
~/.claude/scripts/sync-to-genie.sh --init [skill-name]
```

## 注意事項

- `--watch` はフォアグラウンドプロセスとして動作するため、エージェントからの利用には不向き。都度 push を推奨
- 同期対象は `*.md` ファイルのみ（SKILL.md と handoff-\* は除外）
- `--profile <name>` で Databricks CLI プロファイルを指定可能
