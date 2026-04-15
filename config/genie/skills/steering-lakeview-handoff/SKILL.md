---
name: steering-lakeview-handoff
description: |
  lakeview-handoff.md を読み、Lakeview ダッシュボードのウィジェット JSON を編集する実装側スキル。
  Claude Code / Codex 側が生成した handoff ファイルの指示に従い、ウィジェットを実装し、
  完了後に Implementation Log を追記する。Claude Code 側の同名スキルと対称関係。
  Use when:
  - Lakeview ダッシュボード作業を依頼され、対応する steering task dir に lakeview-handoff.md が存在するとき
  - ウィジェット JSON の追加・変更・修正をするとき
  - 作業完了後に Implementation Log を残すとき
---

# steering-lakeview-handoff (Genie Code 側 - 実装者)

Claude Code / Codex 側で生成された `lakeview-handoff.md` の指示に従い、Lakeview ウィジェット JSON を編集する。

## Step 0: lakeview-pitfalls の先読み (必須)

ウィジェット編集に着手する前に、必ず `lakeview-pitfalls` スキルを Read する:

```
~/.assistant/skills/lakeview-pitfalls/SKILL.md
```

このスキルには以下が**インライン展開**されている:

- 共通ルール Top 5 (encoding type, NULL 処理, FORMAT_NUMBER, 30KB JSON, filter 設計)
- ネガティブリスト Top 5 (bar / line / table / pivot / counter の非対応機能)
- widget 型別ネガティブリスト詳細
- 30KB 超 JSON のデプロイ手順

これを読まずに着手すると、過去セッションで踏んだ pitfall (type 明示で空欄、30KB JSON サイレント切捨、bar 軸カスタム不可で 3 回やり直し等) を繰り返す。

## Step 1: lakeview-handoff.md を読む

steering task ディレクトリから handoff ファイルを特定して読む:

```
/Users/<current-user>/steering/<owner--repo>/<task-dir>/lakeview-handoff.md
```

`<current-user>` は現在の workspace ユーザー名に読み替える。

handoff.md の以下のセクションを必ず確認する:

- **背景**: 変更の目的とステークホルダー
- **データセット**: 既に Claude Code 側で確定済み。SQL を変えてはいけない
- **ページ・ウィジェット仕様**: 実装すべき内容の本体
- **絶対に触らない**: SQL 本体・データセット名・dashboard_id (これらを変えると Claude Code 側に戻すフローが必要)
- **受入条件**: 完了判定の基準
- **既知制約**: 各ウィジェット仕様内に記載された Lakeview 制約 (要確認)

## Step 2: ウィジェット JSON 編集

handoff の指示に従ってダッシュボード JSON を編集する。

### 編集の流れ

1. 現在のダッシュボード JSON を取得 (UI export または `databricks lakeview get <DASHBOARD_ID> --output json`)
2. handoff 指定の各 widget を順次編集
3. encoding の `type` 明示、NULL 処理、FORMAT_NUMBER 等の共通ルールを徹底
4. ネガティブリスト記載の非対応機能を**使わない** (必要なら handoff の代替策に従う)
5. レイアウト (width / height / position) を handoff 通りに設定

### ウィジェット JSON 構造を知りたいとき

handoff の widget 仕様で encoding / format / レイアウトは明示されているが、JSON の細部 (例: pivot の rows/columns/cell の組み立て、bar の encoding/mark の入れ子) を知りたい場合は:

1. 既存ダッシュボードの JSON エクスポート (`databricks lakeview get <ID> --output json`) で似た構造を参考にする
2. Databricks Lakeview 公式ドキュメント (Vega-Lite ベースの encoding 仕様) を参照
3. それでも不明な場合は `lakeview-handoff.md` の Open Questions セクションに記載し、Claude Code 側に質問

### サイズ確認

編集後、JSON サイズを確認:

```bash
wc -c dashboard.json
```

30KB を超えていれば UI 貼り付け不可、CLI で更新する:

```bash
databricks lakeview update <DASHBOARD_ID> --json @dashboard.json
```

## Step 3: 「絶対に触らない」制約の遵守

handoff の "絶対に触らない" セクションに列挙された項目は変更禁止:

- SQL 本体 (dbt mart 参照部) → 変更が必要なら Claude Code 側に戻す
- データセット名 → 変更すると参照が壊れる
- dashboard_id → 変更不要

これらの変更が必要だと感じた場合、**実装を止めて handoff の Open Questions に記載**し、Claude Code 側にレビューを依頼する。

## Step 4: Implementation Log 追記

実装完了後、`lakeview-handoff.md` の末尾 "Implementation Log" セクションに追記する。

### 追記フォーマット

```markdown
<!-- YYYY-MM-DD (vXX): <widget> を <変更内容>。理由: <理由>。 -->
```

### 例

```markdown
<!-- 2026-04-15 (v3): bar widget の axis.values 設定を削除 (Lakeview で非対応のため)。代わりに ORDER BY で並び制御。 -->
<!-- 2026-04-15 (v4): 全ページ pivot widget の cell 構造を multi-cell 形式に変換 (Databricks 公式ドキュメント参照)。 -->
<!-- 2026-04-15 (v5): JSON サイズ 35KB 到達のため CLI 経由で更新。`databricks lakeview update <ID> --json @file.json` を使用。 -->
```

各エントリには **何を変えたか + 理由** を含める。Claude Code 側が pull 後に読んで feedback memory / constraints.md を更新する材料になる。

## Step 5: 受入条件の確認

handoff の "受入条件" を 1 つずつ確認し、すべて満たしていることを確認してから完了報告する。

満たせない条件があれば、Implementation Log にその旨と理由を記載し、Claude Code 側に戻す。

## 注意事項

### 30KB 超 JSON の扱い

詳細は `lakeview-pitfalls` SKILL.md の "30KB 超 JSON のデプロイ手順" 参照。

- UI 貼り付けはサイレントに切り捨てる
- CLI 経由 (`databricks lakeview update`) で更新する
- 更新後に `databricks lakeview get` で差分確認する

### handoff にない要望の処理

ステークホルダーから handoff 範囲外の追加要望が来た場合:

1. 一度作業を止める
2. 追加要望を Implementation Log の末尾に "Out-of-scope request" として記録
3. Claude Code 側に handoff 更新を依頼

handoff のスコープを勝手に拡大しない。

## 関連スキル

- `lakeview-pitfalls` (workspace `.assistant/skills/lakeview-pitfalls`): pitfall 回避カタログ + 共通ルール。Step 0 で必須先読み
- Claude Code 側 `steering-lakeview-handoff`: 本スキルが読む handoff を生成する対称スキル
