# Steering コンテキスト自動取得 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** steering スキル発動時に steering-research エージェントで既存ドキュメントを自動取得し、作業コンテキストに反映する

**Architecture:** steering スキルの SKILL.md にモード判定前の Phase 0 を追加。steering-research エージェント（haiku）にサブエージェント委譲して要約を取得し、メインコンテキスト消費を最小化する。skill-triggers ルールにも自動取得の説明を追記。

**Tech Stack:** Markdown（スキル定義・ルール定義）

---

### Task 1: steering スキルに Phase 0 を追加

**Files:**

- Modify: `config/agents/skills/steering/SKILL.md:9-24` (目的・使用タイミングセクション)
- Modify: `config/agents/skills/steering/SKILL.md:25-30` (Mode 1 の前に Phase 0 挿入)

- [ ] **Step 1: 「スキルの目的」セクションに自動コンテキスト取得を追加**

`config/agents/skills/steering/SKILL.md` の目的リストに追加:

```markdown
- **作業開始時の自動コンテキスト取得**（steering-research エージェント経由）
```

- [ ] **Step 2: 「使用タイミング」セクションに Phase 0 を追加**

既存の番号を繰り下げ、先頭に追加:

```markdown
1. **作業開始時（自動）**: steering-research で既存ドキュメントのコンテキストを取得
2. **作業計画時**: ステアリングファイルを作成する時
3. **実装時**: tasklist.mdに従って実装する時
4. **検証時**: 実装完了後の振り返りを記録する時
```

- [ ] **Step 3: Mode 1 の前に「Phase 0: コンテキスト取得」セクションを挿入**

`## モード1: ステアリングファイル作成` の直前に以下を挿入:

```markdown
## Phase 0: コンテキスト自動取得（全モード共通）

### 目的

モード判定の前に、現リポジトリの既存 steering ドキュメントを自動取得する。
steering-research エージェント（haiku）に委譲することで、メインコンテキストの消費を最小限に抑える。

### 手順

1. **リポジトリ名の自動検出**（モード1の手順1と同じロジック）

   `git remote get-url origin` → `owner--repo` 形式に変換

2. **steering-research エージェントに問い合わせ**

   Agent ツールで steering-research を起動し、以下のプロンプトを渡す:
```

現リポジトリ {owner}--{repo} の steering ドキュメントを検索し、以下を要約してください:

1.  進行中のタスク (status: in_progress または pending) の一覧
    - 各タスク: タイトル、ステータス、完了率、現在のフェーズ
2.  直近で完了したタスク (status: done) があれば、タイトルのみ

検索ベース: ~/.local/state/steering/{owner}--{repo}/
ドキュメントが見つからない場合は「該当なし」と報告してください。

```

3. **結果に基づくモード判定**

- **進行中タスクあり**: ユーザーの作業指示と関連するタスクがあれば Mode 2（実装）に進む
- **進行中タスクなし / 該当なし**: Mode 1（新規作成）に進む
- ユーザーが明示的にモードを指定した場合はそちらを優先

### コンテキスト節約の仕組み

- steering-research（haiku モデル）がサブエージェントとして検索・読み込みを実行
- メインコンテキストに載るのは**要約のみ**（数百トークン程度）
- 生の steering ドキュメント全文はメインコンテキストに載らない
- 必要に応じて個別ファイルを Read する判断はモード判定後に行う
```

- [ ] **Step 4: 変更後の SKILL.md を通読して整合性を確認**

Phase 0 で取得した owner--repo がモード1の手順1と重複しないよう、モード1側に「Phase 0 で取得済みの場合はスキップ」の注記を追加:

```markdown
1. **リポジトリ名の自動検出**

   > Phase 0 で既に取得済みの場合、この手順はスキップする。
```

- [ ] **Step 5: Commit**

```bash
git add config/agents/skills/steering/SKILL.md
git commit -m "feat(steering): add Phase 0 auto context loading via steering-research agent"
```

### Task 2: skill-triggers ルールに自動取得の説明を追記

**Files:**

- Modify: `config/agents/rules/skill-triggers.md:8-17` (steering セクション)

- [ ] **Step 1: steering セクションにコンテキスト自動取得の説明を追記**

`config/agents/rules/skill-triggers.md` の steering セクション、省略条件の後に追加:

```markdown
**コンテキスト自動取得**: steering スキル発動時、モード判定の前に
steering-research エージェントを使って現リポジトリの進行中タスクを自動取得する。
これにより過去の要件・設計が自動的に作業コンテキストに反映される。
```

- [ ] **Step 2: Commit**

```bash
git add config/agents/rules/skill-triggers.md
git commit -m "docs(rules): document steering auto context loading in skill-triggers"
```

### Task 3: 動作確認

- [ ] **Step 1: pre-commit で品質チェック**

```bash
cd /Users/kumewataru/dotfiles && pre-commit run --all-files
```

Expected: All checks passed

- [ ] **Step 2: nix fmt でフォーマット確認**

```bash
cd /Users/kumewataru/dotfiles && nix fmt
```

Expected: No changes (Markdown files are not formatted by nix fmt, but confirm no breakage)
