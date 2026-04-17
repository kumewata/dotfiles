---
name: steering-lakeview-handoff
description: |
  Lakeview ダッシュボード開発で Genie Code に渡す lakeview-handoff.md を生成・更新するスキル。
  Claude Code / Codex 側で SQL とデータセット設計を確定した後、ウィジェット実装を Genie Code に委譲するためのハンドオフ契約書を作る。
  Genie Code 側の同名スキル (steering-lakeview-handoff) と対称関係。
  Use when:
  - Databricks Lakeview ダッシュボードの SQL/データセット設計が完了し、Genie Code にウィジェット実装を渡したいとき
  - lakeview-handoff.md を生成・更新したいとき
  - Genie Code が追記した Implementation Log を pull 後に読み込み、feedback memory に反映したいとき
---

# steering-lakeview-handoff (Claude Code / Codex 側 - 設計者)

steering 済みの Lakeview ダッシュボードタスクで、Genie Code へのハンドオフ契約書 `lakeview-handoff.md` を生成する。

## 発動条件

すべて満たす場合に発動:

- 作業対象が Databricks Lakeview ダッシュボード
- steering スキルが既に実行済みで `~/.local/state/steering/<owner>--<repo>/<task-dir>/requirements.md` と `design.md` が存在
- SQL / データセット設計が固まり、ウィジェット実装を Genie Code に渡すフェーズ

## Lakeview 制約サマリー (必読・インライン)

設計時にこれらの制約を **要件・データセット定義に反映** すること。`references/constraints.md` に詳細表あり。

- **bar**: 軸カスタムソート / データラベル / Marimekko **非対応** → SQL ORDER BY で並びを制御、title で補足
- **line**: セグメント連結 (gap bridging) **非対応** → SQL 側で COALESCE による NULL 埋め
- **table**: encoding の `type` を **省略禁止** → 必ず `quantitative` / `nominal` / `temporal` / `ordinal` を明示。**ただし新規追加カラムでは type 明示で逆に空欄になるケースあり** (Lakeview スキーマキャッシュ問題、要 case-by-case 検証)
- **pivot**: セル内条件付き書式 / 小計行 **非対応** → SQL で UNION ALL による小計行展開
- **counter**: 1 ウィジェット 1 KPI → 複数値は counter を並べて配置
- **共通**: NULL 表示は SQL 側で `COALESCE(col, '—')`、数値整形は SQL 側で `FORMAT_NUMBER(val, '#,##0')`
- **>30KB JSON**: UI 貼り付け不可 → `databricks lakeview update <ID> --json @file.json` 経由
- **filter**: ウィジェット単位の fine-grained 制御不可 → ページレベルパラメータで設計

## 手順

### Step 1: 前提確認

```bash
# steering task dir のパスを特定
TASK_DIR=~/.local/state/steering/<owner>--<repo>/<YYYYMMDD-task-name>/

# 必須ファイルの存在確認
test -f "$TASK_DIR/requirements.md" && test -f "$TASK_DIR/design.md" || echo "steering 未完了"
```

### Step 2: 制約早見表を読む

`references/constraints.md` を Read し、設計で使うウィジェット型に対する制約が `design.md` のクエリ設計・データセット仕様に反映されているか確認する。反映漏れがあれば design.md を先に更新する。

### Step 3: テンプレートを読む

`templates/lakeview-handoff.md.tmpl` を Read する。

### Step 4: lakeview-handoff.md を生成

テンプレートのプレースホルダー (`<...>`) を埋めて `<TASK_DIR>/lakeview-handoff.md` に書き出す。

埋めるべき項目:

- frontmatter: `task`, `dashboard_id`, `source_steering`, `generated_at`
- 背景: requirements.md から 2-3 行で要約 (ステークホルダーと期限も)
- データセット: SQL 配置パス、スキーマ表、dbt/Snowflake 依存
- ページ・ウィジェット仕様: ページ名 → ウィジェット仕様（type, encoding, format, レイアウト, **既知制約**)
- 絶対に触らない: SQL 本体、データセット名、dashboard_id
- 受入条件: 検証可能な箇条書き
- Implementation Log: 空 (基本は Genie Code が直接追記、書き戻し失敗時はフォールバック経由で Claude Code が追記)

### Step 5: Genie Code workspace に push

```bash
~/.claude/scripts/sync-to-genie.sh "$TASK_DIR"
```

push 後、Genie Code セッション側で同タスクディレクトリ内の `lakeview-handoff.md` が読み取れるようになる。

### Step 6: Implementation Log の取り込み (二段構え)

Genie Code の実装完了後、Implementation Log を取り込む。

#### 6a. 基本フロー: pull して確認

```bash
~/.claude/scripts/sync-to-genie.sh --pull "$TASK_DIR"
```

`lakeview-handoff.md` の "Implementation Log" セクションに Genie Code が直接追記していれば (基本フロー成功)、その内容をそのまま確認して完了。

#### 6b. フォールバック: ユーザーから受け取って追記

pull 後に Implementation Log が空 (Genie Code の書き戻しが失敗していた場合):

1. ユーザーから Genie Code チャット欄の **Implementation Report** を受け取る (ペーストまたは自然言語で伝達)
2. 受け取った内容を `lakeview-handoff.md` の "Implementation Log" セクションに追記する
3. `sync-to-genie.sh "$TASK_DIR"` で workspace 側にも反映

#### 6c. 共通: 学びの反映

取り込み方法を問わず、Implementation Log の内容から:

- 今後の handoff に活かせる学び (ハマったポイント、効いた対策) を feedback memory に保存
- 必要なら `references/constraints.md` を更新（同じ pitfall を二度踏まないため）
- tasklist.md の進捗を更新

## テンプレートの使い方

`templates/lakeview-handoff.md.tmpl` は **そのままコピーして** `<TASK_DIR>/lakeview-handoff.md` に置く。プレースホルダー `<...>` は全て具体値で置き換えること。空欄のまま push しない。

ウィジェットが複数ある場合は、Widget セクション (`#### Widget X.Y: ...`) を必要数だけ複製する。

## 関連スキル

- `databricks-steering-sync`: workspace との push/pull 操作の詳細
- `steering`: requirements.md / design.md / tasklist.md の管理
- Genie Code 側 `steering-lakeview-handoff` (workspace `.assistant/skills/`): 本スキルが生成した handoff を読んで実装する対称スキル
- Genie Code 側 `lakeview-pitfalls` (workspace `.assistant/skills/`): Genie Code がウィジェット編集時に必ず読む pitfall カタログ
