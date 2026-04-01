---
name: steering
description: Use when the user asks for a plan, implementation checklist, task breakdown, progress tracking, or a durable task artifact for a non-trivial task. Also use when creating or updating steering documents such as requirements, design, or tasklist files under ~/.local/state/steering. Do NOT use for simple Q&A, lightweight investigation with no artifact, or single-file obvious edits that do not need planning. Trigger especially on requests like "改善プラン", "実装計画", "タスクリスト", "進捗管理", or "steeringを使って".
allowed-tools: Read, Write
---

# Steering スキル

中央集約型ディレクトリ（`~/.local/state/steering/`）に基づいた実装を支援し、tasklist.mdの進捗管理を確実に行うスキルです。

## スキルの目的

- ステアリングファイル（requirements.md, design.md, tasklist.md）の作成支援
- tasklist.mdに基づいた段階的な実装管理
- **進捗の自動追跡とtasklist.md更新の強制**
- 実装完了後の振り返り記録
- **リポジトリ横断タスクの一元管理**

## 使用タイミング

1. **作業計画時**: ステアリングファイルを作成する時
2. **実装時**: tasklist.mdに従って実装する時
3. **検証時**: 実装完了後の振り返りを記録する時

## モード1: ステアリングファイル作成

### 目的

新しい機能や変更のためのステアリングファイルを作成します。

### 手順

1. **リポジトリ名の自動検出**

   現在の作業ディレクトリから `owner/repo` 形式のリポジトリ名を取得する:

   ```
   Step 1: git リポジトリかどうか判定
     $ git rev-parse --is-inside-work-tree

   Step 2A (git リポジトリ + remote あり):
     $ git remote get-url origin
     → origin が存在しない場合: $ git remote | head -1 で最初の remote を使用
     → URL を解析して owner/repo を抽出
     URL パターン:
       git@github.com:owner/repo.git  → owner/repo
       https://github.com/owner/repo.git → owner/repo
       https://github.com/owner/repo → owner/repo
       （GitLab 等も同様: ホスト名の後の最後の2パスセグメント）

   Step 2B (git リポジトリ + remote なし):
     → local/<basename of git toplevel> を使用

   Step 2C (git リポジトリ外の場合):
     → local/<basename of pwd> を使用

   Step 3 (worktree の場合):
     $ git rev-parse --git-common-dir
     → メインリポジトリのルートを取得し、そこで Step 2A/2B を再実行して owner/repo を解決
   ```

   **ディレクトリ名への変換**: `owner/repo` のスラッシュをダブルハイフン (`--`) に変換する。
   例: `kumewata/dotfiles` → `kumewata--dotfiles`、`local/scripts` → `local--scripts`

2. **ステアリングディレクトリの作成**

   ```
   現在の日付を取得し、`~/.local/state/steering/<owner>--<repo>/[YYYYMMDD]-[機能名]/` の形式でディレクトリを作成
   ```

3. **プロジェクトドキュメントの確認**

   プロジェクトの方針を理解するために、以下のドキュメントがあれば確認する:
   - CLAUDE.md（プロジェクトルール）
   - README.md（プロジェクト概要）
   - プロジェクト固有の設計書・仕様書（docs/ など）

4. **軽量モード判定**

   以下のいずれかに該当する場合、**軽量モード**（tasklist.md のみ）で進める:
   - 調査・分析タスク（コード変更なし）
   - 単一ファイルの修正で設計判断が不要
   - 既存設計に従った定型作業

   軽量モードの場合:
   - tasklist.md のみ作成（requirements.md, design.md は省略）
   - ユーザーに「軽量モードで進めます」と報告
   - 以下の雛形で tasklist.md を作成:

   ```yaml
   ---
   title: { タスク名 }
   tags: [調査, タスク管理]
   mode: lightweight
   related: []
   repos:
     - { owner/repo }
   branch: { branch-name }
   status: pending
   completion: 0%
   ---
   ```

   フェーズ構成（軽量モード専用）:

   ```markdown
   ## フェーズ1: 調査・分析

   - [ ] {調査タスク}

   ## フェーズ2: 成果物作成

   - [ ] {分析結果のドキュメント化}

   ## フェーズ3: レビュー・報告

   - [ ] 成果物の確認
   - [ ] 実装後の振り返り
   ```

5. **テンプレートからファイル作成**（通常モード）

   以下のテンプレートを読み込み、プレースホルダーを具体的な内容に置き換えてファイルを作成:
   - `~/.claude/skills/steering/templates/requirements.md` → `requirements.md`
   - `~/.claude/skills/steering/templates/design.md` → `design.md`
   - `~/.claude/skills/steering/templates/tasklist.md` → `tasklist.md`

   出力先: `~/.local/state/steering/<owner>--<repo>/YYYYMMDD-[機能名]/`

6. **YAML Front Matter の記入**

   ### 自動生成フィールド
   - **title**: プロジェクト名から自動抽出
   - **related**: 通常モードは3ファイル（requirements.md, design.md, tasklist.md）、軽量モードは `[]`
   - **repos**: `owner/repo` をリスト形式で設定
   - **branch**: `git rev-parse --abbrev-ref HEAD` で取得（detached HEAD の場合は省略）
   - **status**: 初期値 `pending`（tasklist.md のみ）
   - **completion**: 初期値 `0%`（tasklist.md のみ）

   ### ユーザー入力推奨フィールド
   - **tags**: カテゴリ分類（3-8個）
     - requirements.md: "要件", "スコープ" + ドメイン固有タグ
     - design.md: "設計", "アーキテクチャ" + 技術スタック
     - tasklist.md: "実装", "タスク管理" + フェーズ名

   - **use_when**: **最重要フィールド**。参照すべき状況をユーザーの言葉で記述

   - **keywords**: プロジェクト固有の固有名詞（API名、コンポーネント名等）

   - **references**: 関連する外部リンク（GitHub Issue/PR/Discussion 等のURL）

   ### Front Matter 記入例

   ```yaml
   ---
   title: Nix Flakes のマルチデバイス対応
   tags: [要件, スコープ, Nix, マルチデバイス]
   use_when: >
     - Nix Flakes でマルチデバイス対応の要件を確認したいとき
     - ユーザー名の動的解決の要件を確認したいとき
   keywords: [Nix, Home Manager, builtins.getEnv, --impure]
   references:
     - "https://github.com/kumewata/dotfiles/issues/1"
   related:
     - design.md
     - tasklist.md
   repos:
     - kumewata/dotfiles
   branch: main
   ---
   ```

7. **design.md のドメイン別セクション選択**

   design.md テンプレートにはオプションスタブ（HTMLコメント）が含まれる。タスクのドメインに応じて該当セクションを有効化し、不要なコメントを削除する:
   - **dbt**: モデル設計（stg/int/mart 層）、修正戦略/変更箇所一覧、スキーマ設計
   - **Pipeline/Terraform**: インフラ構成、コードテンプレート（HCL例）、エラーハンドリング/リカバリ
   - **Dashboard/BI**: 調査結果サマリ、クエリ設計（SQL/JOIN/パラメータ）、データソース一覧
   - **分析・調査**: design.md 不要（軽量モードを使用）

8. **tasklist.mdの詳細化**

   requirements.mdとdesign.mdに基づいて、tasklist.mdのタスクを具体化。

### 既存 `.steering/` の移行

リポジトリ内に `.steering/` がある場合、中央ディレクトリに移行する:

1. `owner/repo` を取得し `~/.local/state/steering/<owner>--<repo>/` に移動
2. YAML Front Matter に `repos` / `branch` を追加
3. 移行元の `.steering/` を削除

## モード2: 実装（最重要）

### 目的

tasklist.mdに従って実装を進め、**進捗を確実にドキュメントに記録**します。

### 🚨 重要な原則

**tasklist.mdが唯一の進捗管理ドキュメント。** 全タスクを`[x]`にするまで作業を継続すること。タスクのスキップは技術的理由のみ許可。詳細なルールは tasklist.md テンプレートの「🚨 タスク完全完了の原則」セクションを参照。

**MUST**:

- タスク完了時に必ずEditツールで`[ ]`→`[x]`に更新
- 未完了タスクがある状態で作業を終了しない
- tasklist.mdを更新せずに次のタスクに進まない

**NEVER**:

- tasklist.mdを見ずに実装を進める
- 複数タスクをまとめて更新する（リアルタイムに更新する）
- 「時間の都合により」「別タスクとして実施予定」などの理由でタスクをスキップする

### 実装フロー

#### ステップ0: タスク発見（中央ディレクトリからの検索）

1. **リポジトリ名を自動検出**（モード1の手順1と同じ）
2. **直接所属タスクを検索**: `~/.local/state/steering/<owner>--<repo>/` 配下の tasklist.md を走査
3. **横断タスクを検索**（必要な場合）: 全 tasklist.md の `repos` フィールドを検索
4. **アクティブなタスクをフィルタリング**: `status` が `pending` または `in_progress` のみ
5. **ユーザーに作業対象のタスクを提示し、選択してもらう**

#### ステップ1: tasklist.mdを読み込む

```
Read('~/.local/state/steering/<owner>--<repo>/YYYYMMDD-[機能名]/tasklist.md')
```

全体のタスク構造を把握し、次に着手すべきタスクを特定する。

#### ステップ2: タスクループ（各タスクで繰り返す）

**2-1. 次のタスクを確認**

```
tasklist.mdを読み、次の未完了タスク（`[ ]`）を特定
```

**2-2. 実装を実行**

```
プロジェクトのガイドラインに従って実装
```

**2-3. タスク完了をtasklist.mdに記録（必須）**

```
実装完了後、Editツールで該当行を`[ ]`→`[x]`に更新

例:
old_string: "- [ ] StorageServiceを実装"
new_string: "- [x] StorageServiceを実装"

サブタスクがある場合はサブタスクも個別に`[x]`に更新
```

**2-5. 次のタスクへ** → ステップ2-1に戻る

#### ステップ3: フェーズ完了時の確認

各フェーズ完了時に tasklist.md を読み込み、全タスクが`[x]`になっているか確認。ユーザーに報告。

#### ステップ4: 全タスク完了チェック

振り返りを書く前に、未完了タスク（`[ ]`）がないことを確認。未完了がある場合はステップ2に戻る。技術的理由でタスクが不要になった場合のみスキップ可（tasklist.md テンプレートのルールに従う）。

#### ステップ5: 全タスク完了後

tasklist.mdの「実装後の振り返り」セクションをEditツールで更新:

- 実装完了日
- 計画と実績の差分
- 方針変更の記録（該当する場合）
- 学んだこと
- 後続タスク（該当する場合）
- 次回への改善提案

### 実装中のセルフチェック

5タスクごとに確認: tasklist.mdを最近更新したか？ 進捗がドキュメントに反映されているか？

## モード3: 振り返り

### 目的

実装完了後、tasklist.mdに振り返りを記録します。

### 手順

1. tasklist.mdを読み込み、全タスクが`[x]`であることを確認
2. 振り返り内容を作成（実装完了日、差分、方針変更の記録、学び、後続タスク、改善提案）
3. Editツールで「実装後の振り返り」セクションを更新
4. ユーザーに報告

## トラブルシューティング

### tasklist.mdの更新を忘れた場合

1. 即座に tasklist.md を読み込み、完了タスクを特定して`[x]`に更新
2. ユーザーに報告
3. 次のタスクから確実に更新する

### tasklist.mdと実装の乖離

1. Editツールで該当タスクに注釈を追加: `- [x] タスク名（実装方法を変更: 理由）`
2. 必要に応じて新しいタスクを追加
3. 設計変更が大きい場合は design.md も更新

## チェックリスト

実装前: tasklist.md読み込み → 次タスク特定
実装後: Edit で`[x]`更新 → 進捗確認 → ユーザーが見て分かる状態か？

## 重要なリマインダー

**tasklist.mdこそが永続的な進捗ドキュメント（ユーザーが見る）。** 実装中は常に「ユーザーがtasklist.mdを見たときに進捗が分かるか？」を自問してください。
