---
name: lakeview-pitfalls
description: |
  Lakeview ダッシュボードのウィジェット JSON 編集時に踏みやすい pitfall の回避策と共通ルールを提供する参照スキル。
  ウィジェット編集前に必ず読むこと。
  Use when:
  - Lakeview ウィジェットの JSON を編集するとき
  - bar / line / table / pivot / counter / pie のいずれかを扱うとき
  - 30KB を超える JSON のデプロイが必要なとき
  - encoding type / NULL 表示 / 数値整形 / filter の設計判断をするとき
---

# Lakeview Pitfalls

> **このスキルの位置付け**: Lakeview ウィジェット編集時の **横断的な pitfall カタログと共通ルール** をまとめた主参照スキル。ウィジェットの JSON 構造の細部 (rows/columns/cell の組み立て等) は、ハンドオフファイルの仕様 + 既存ダッシュボードの JSON エクスポート + Databricks 公式ドキュメントを参照する。

このスキルは Databricks workspace 上では SKILL.md 単体としてデプロイされるため、参照ファイル (references/) は workspace 上に存在しない。**主要情報はすべて本ファイルにインライン化されている**。

---

## 共通ルール Top 5 (インライン要約)

1. **encoding `type` は必ず明示する** (`quantitative` / `nominal` / `temporal`)。省略すると列が空欄になるバグを踏む
2. **NULL は SQL 側で `COALESCE(col, '—')` に変換**。JSON 側で NULL 表示制御は不可
3. **数値整形は SQL 側で `FORMAT_NUMBER(val, '#,##0')` を適用**。JSON 側 `numberFormat` は制限多い
4. **30KB 超の JSON は UI 貼り付け不可** (サイレント切捨)。`databricks lakeview update <ID> --json @file.json` で CLI 経由更新
5. **filter はウィジェット単位で fine-grained 設定不可**。ページレベルパラメータで設計

## ネガティブリスト Top 5 (インライン要約)

1. **bar**: 軸カスタムソート / データラベル / Marimekko **非対応**
2. **line**: セグメント連結 (gap bridging) **非対応** (NULL 行で線が途切れる)
3. **table**: encoding `type` 省略 → **列が消える**
4. **pivot**: セル内条件付き書式 / 小計行 **非対応**
5. **counter**: 1 ウィジェット 1 値。複数値の並列表示 **非対応**

---

## widget 型別ネガティブリスト (詳細)

### bar

| 非対応機能         | 詳細                                        | 代替策                                      |
| ------------------ | ------------------------------------------- | ------------------------------------------- |
| 軸のカスタムソート | `axis.sort` で任意順序を指定不可            | SQL `ORDER BY` で並びを SQL 側で固定        |
| データラベル表示   | `mark.showLabels` 等の指定が無視される      | tooltip で代替、または title でサマリ表示   |
| Marimekko          | 横幅と高さの両方をカテゴリ別に変える表現    | bar + 別カラムで近似                        |
| Y軸目盛りカスタム  | `axis.values` / `axis.tickCount` が効かない | 軸範囲を限定したい場合は SQL でデータを絞る |

実プロジェクトのダッシュボード開発で v10-v12 にかけて 3 回やり直した実例あり。

### line

| 非対応機能     | 詳細                                            | 代替策                                       |
| -------------- | ----------------------------------------------- | -------------------------------------------- |
| セグメント連結 | NULL 行があると線が途切れる (gap bridging なし) | SQL 側で `COALESCE(col, 0)` 等で NULL 埋め   |
| 多色凡例       | 凡例の並び順カスタム不可                        | SQL 側でラベル接頭辞 (`'01_xxx'`) で順序制御 |

### table

| 非対応機能               | 詳細                      | 代替策                                |
| ------------------------ | ------------------------- | ------------------------------------- |
| encoding `type` 省略     | 推論失敗で列が空欄になる  | `"type": "quantitative"` 等を必ず明示 |
| 行クリックでドリルダウン | カスタムリンク等 設定不可 | 別ダッシュボードへの link tile で代替 |

### pivot

| 非対応機能         | 詳細                             | 代替策                            |
| ------------------ | -------------------------------- | --------------------------------- |
| セル内条件付き書式 | セル値による色付け 不可          | 色付け不要なメトリクスに絞る      |
| 小計行             | 自動小計表示 不可                | SQL `UNION ALL` で小計行を行展開  |
| 行・列の動的入替   | UI で自由に入替不可 (定義時固定) | rows / columns を要件確定後に設計 |

### counter

| 非対応機能       | 詳細                                       | 代替策                                |
| ---------------- | ------------------------------------------ | ------------------------------------- |
| 複数値の並列表示 | 1 counter で複数 KPI を表示 不可           | counter を複数配置 (1 widget = 1 KPI) |
| 値の比較表示     | 前年比などを副表示 不可 (counter 単体では) | counter + bar / line で構成           |

### pie

| 非対応機能   | 詳細                           | 代替策                         |
| ------------ | ------------------------------ | ------------------------------ |
| 10+ カテゴリ | 多すぎると凡例で潰れて読めない | SQL で TOP N + "その他" に集約 |
| ドーナツ     | 内側ラベル設定 不可            | bar に変更を検討               |

---

## 共通ルール (詳細)

### encoding `type` 明示ルール

**根拠**: Lakeview の encoding は `type` を明示しないと SQL の型から推論しようとするが、スキーマキャッシュ不一致や型推論失敗で **列が空欄になる**。

```json
// NG (列が空欄になる)
{
  "encoding": {
    "x": { "field": "sales_date" },
    "y": { "field": "revenue" }
  }
}

// OK
{
  "encoding": {
    "x": { "field": "sales_date", "type": "temporal" },
    "y": { "field": "revenue", "type": "quantitative" }
  }
}
```

`type` の値: `"quantitative"` (数値) / `"nominal"` (カテゴリ) / `"temporal"` (日時) / `"ordinal"` (順序つきカテゴリ)

**例外 (table widget)**: table の場合、**新規追加カラムで type を明示すると逆に空欄になる**ケースがある (Lakeview 側のスキーマキャッシュ不一致)。table の新規カラム追加時は、まず type 省略で Lakeview 推論に任せる方が安全。既存カラムは type 明示で問題ない。要 case-by-case 検証。

### NULL 処理パターン

JSON 側で `nullValue` / `defaultValue` 設定は **未対応**。NULL を表示したい/ハイフンに変えたい場合は **SQL 側で対処**。

```sql
-- NULL を "—" に置換
SELECT
  shop_name,
  COALESCE(CAST(revenue AS STRING), '—') AS revenue_display,
  COALESCE(growth_rate, 0) AS growth_rate
FROM mart_sales
```

数値計算が後段で必要なら `COALESCE(col, 0)`、表示専用なら `COALESCE(CAST(col AS STRING), '—')`。

### `FORMAT_NUMBER` の使い方

```sql
-- 整数カンマ区切り
FORMAT_NUMBER(revenue, '#,##0')  -- 1,234,567

-- 小数 2 桁
FORMAT_NUMBER(growth_rate, '0.00')  -- 12.34

-- パーセント (0.1234 → 12.34%)
CONCAT(FORMAT_NUMBER(growth_rate * 100, '0.00'), '%')
```

JSON 側の `numberFormat` も存在するが、桁区切り・パーセント表示で動作が安定しないため SQL 側で整形済み文字列を用意するのが安全。

### filter 設計原則

- ウィジェット個別フィルタは **不可** (1 つ設定すると全ウィジェットに適用される)
- ページレベルパラメータは **OK** (WHERE 句にバインド)

```sql
-- ページパラメータ {{shop_id}} を WHERE 句にバインド
SELECT * FROM mart_sales
WHERE shop_id = {{shop_id}}
```

ウィジェット個別の絞り込みが必要なら、別データセットを作って事前絞り込みする。

---

## 30KB 超 JSON のデプロイ手順

### サイズ確認

```bash
# JSON サイズを確認
wc -c dashboard.json

# 30000 (30KB) を超えていれば UI 貼り付け不可
```

### CLI 経由更新

```bash
# Lakeview ダッシュボードを CLI で更新
databricks lakeview update <DASHBOARD_ID> --json @dashboard.json
```

`@` プレフィックスでファイル指定する。stdin 経由は同様にサポート:

```bash
cat dashboard.json | databricks lakeview update <DASHBOARD_ID> --json -
```

### UI 貼り付けが失敗するパターン

- 30KB を境に **サイレントに JSON が切り捨てられ**、パースエラーが UI 上に出ない
- ダッシュボードが部分的に表示されたり、特定ページが消える
- **症状で気付くまで時間がかかる**ため、サイズ確認を更新前に必ず行う

### サイズ削減のテクニック

サイズが大きすぎる場合:

- ページを分割して別ダッシュボードにする
- 似たウィジェットを統合する (bar 複数 → pivot 1 つ)
- 不要な `description` / `comment` フィールドを削除

---

## 詳細参照 (ローカル保守用)

`config/genie/skills/lakeview-pitfalls/references/` にローカル保守用のファイルがある (workspace にはデプロイされない):

- `widget-negatives.md`: widget 型別の非対応機能カタログ (本 SKILL.md と同内容)
- `common-rules.md`: 共通ルールの詳細とコード例 (本 SKILL.md と同内容)
- `large-json.md`: 30KB JSON デプロイ手順詳細 (本 SKILL.md と同内容)

新しい pitfall を発見した場合、まず本 SKILL.md を更新し (workspace 反映のため)、次に references/ も同期する。

## 関連スキル

- Genie Code 側 `steering-lakeview-handoff`: lakeview-handoff.md を読んでウィジェット実装するスキル。本スキルを Step 0 で先読みする

## ウィジェット JSON 構造の詳細を知りたいとき

このスキルは pitfall と共通ルールに特化している。ウィジェット型ごとの JSON 構造 (例: pivot の rows/columns/cell の組み立て、bar の encoding/mark の入れ子) を知りたい場合は次の順で参照する:

1. **handoff.md の widget 仕様** — 該当ウィジェットの encoding / format / レイアウトが明示されている
2. **既存ダッシュボードの JSON エクスポート** — `databricks lakeview get <DASHBOARD_ID> --output json` で取得できる、似た構造のウィジェットを参考にする
3. **Databricks Lakeview 公式ドキュメント** — Vega-Lite ベースの encoding 仕様
