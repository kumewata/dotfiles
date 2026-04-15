# Lakeview Large JSON Deployment

ローカル保守用。Databricks workspace にはデプロイされない。SKILL.md と内容を同期する。

## 30KB 閾値

Lakeview ダッシュボードの JSON サイズが約 30KB を超えると、**UI 貼り付けがサイレントに切り捨てられる**。エラー表示なしでダッシュボードが部分表示されたり、特定ページが消える症状が出る。

### サイズ確認

```bash
# JSON ファイルのバイト数を確認
wc -c dashboard.json

# 出力例: 31245 dashboard.json
# 30000 を超えていれば UI 貼り付け不可
```

### 確認頻度

- ウィジェット数が増える / pivot で columns が多い場合は逐次確認
- 統括会議ダッシュボード (5 ページ + bar/pivot/line 多数) の実例で 106KB 到達

## CLI 経由の更新手順

### 基本コマンド

```bash
# Lakeview ダッシュボードを CLI で更新
databricks lakeview update <DASHBOARD_ID> --json @dashboard.json
```

`@` プレフィックスでファイル指定 (curl と同じ慣習)。

### stdin 経由

```bash
cat dashboard.json | databricks lakeview update <DASHBOARD_ID> --json -
```

`jq` でフィルタしてから流す等、パイプライン処理に便利。

### dashboard ID の取得

```bash
# ダッシュボード一覧から ID を見つける
databricks lakeview list

# ダッシュボード名で grep
databricks lakeview list --output json | jq '.[] | select(.display_name == "統括会議") | .dashboard_id'
```

### 更新後の確認

```bash
# 更新内容を pull して差分確認
databricks lakeview get <DASHBOARD_ID> --output json > dashboard_remote.json
diff dashboard.json dashboard_remote.json
```

## UI 貼り付けが失敗するパターン

### サイレント切り捨て

- 30KB を境に UI が JSON 末尾を切り捨てる
- パースエラーが UI 上に表示されない
- 結果として部分的にダッシュボードが表示されたり、特定 widget / page が消える

### 症状の見分け方

- 編集前と編集後で widget 数が違う
- 特定ページが消える
- ブラウザ Dev Tools で truncated JSON が見える

### 対処

- UI 貼り付けは諦める
- CLI コマンドに切り替え
- サイズ削減を試みる (下記)

## サイズ削減テクニック

### 1. ページ分割

5 ページの大ダッシュボードを 2-3 個のダッシュボードに分割。トップページに link tile で他ダッシュボードへ誘導。

### 2. ウィジェット統合

似た bar チャート 5 つ → pivot 1 つで集約。SQL の GROUP BY を増やして表現する。

### 3. 不要フィールド削除

JSON 内の以下を削除可能:

- `description` / `comment` (空のまま残っているケースが多い)
- 旧バージョンの `legacy_*` フィールド
- 重複する `encoding` 設定 (デフォルト値なら省略可)

### 4. データセット重複の解消

複数 widget が同じ SQL を参照している場合、データセットを共有化して JSON 内の SQL 重複を削減。

## 既知の症状例

| サイズ   | 症状                          | 対処                   |
| -------- | ----------------------------- | ---------------------- |
| ~25KB    | 問題なし                      | UI 貼り付け OK         |
| 25-30KB  | 環境依存で切り捨てる場合あり  | CLI 推奨               |
| 30-100KB | UI 貼り付けで widget が消える | CLI 必須               |
| 100KB+   | UI 貼り付けで全体が壊れる     | CLI + サイズ削減を検討 |
