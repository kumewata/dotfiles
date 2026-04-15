# Lakeview Common Rules (詳細)

ローカル保守用。Databricks workspace にはデプロイされない。SKILL.md と内容を同期する。

## encoding `type` 明示ルール

### 根拠

Lakeview は `encoding.type` を明示しないと SQL 結果から推論しようとするが、スキーマキャッシュ不一致や型推論失敗で**列が空欄になる**。

### コード例

```json
// NG: 列が空欄
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

### `type` の取り得る値

- `"quantitative"` — 数値 (集計可能)
- `"nominal"` — カテゴリ (順序なし)
- `"ordinal"` — 順序つきカテゴリ
- `"temporal"` — 日時

### 注意点 (table widget)

table の場合、**新規追加カラムで type を明示すると逆に空欄になる**ケースがある (Lakeview 側のスキーマキャッシュ問題)。table の新規カラムでは type 省略で Lakeview に推論させる方が安全な場合がある (要 case-by-case 検証)。

## NULL 処理パターン

### JSON 側の制限

- `nullValue` 設定: **未対応**
- `defaultValue` 設定: **未対応**
- NULL 表示制御は SQL 側で完結させる必要あり

### SQL パターン

```sql
-- 表示用: NULL を "—" (em dash) に置換
SELECT
  shop_name,
  COALESCE(CAST(revenue AS STRING), '—') AS revenue_display
FROM mart_sales

-- 計算用: NULL を 0 として扱う
SELECT
  shop_name,
  COALESCE(revenue, 0) AS revenue,
  COALESCE(growth_rate, 0) AS growth_rate
FROM mart_sales

-- 比較用: NULL を別の値で埋めて条件分岐
SELECT
  shop_name,
  CASE
    WHEN revenue IS NULL THEN 'データなし'
    WHEN revenue >= goal THEN '達成'
    ELSE '未達'
  END AS status
FROM mart_sales
```

### 表示用と計算用の使い分け

- 後段で集計が必要 → `COALESCE(col, 0)`
- 表示専用 → `COALESCE(CAST(col AS STRING), '—')`
- 両方必要 → カラムを分ける (例: `revenue` 数値版 + `revenue_display` 文字列版)

## `FORMAT_NUMBER` の使い方

### 基本パターン

```sql
-- 整数カンマ区切り (1,234,567)
FORMAT_NUMBER(revenue, '#,##0')

-- 小数 2 桁 (12.34)
FORMAT_NUMBER(growth_rate, '0.00')

-- 千単位カンマ + 小数 2 桁 (1,234.56)
FORMAT_NUMBER(amount, '#,##0.00')

-- パーセント表示 (12.34%)
CONCAT(FORMAT_NUMBER(growth_rate * 100, '0.00'), '%')

-- 通貨表示 (¥1,234,567)
CONCAT('¥', FORMAT_NUMBER(revenue, '#,##0'))
```

### JSON 側 `numberFormat` を避ける理由

- 桁区切りカスタムが効かないケースあり
- パーセント表示の動作が widget 型で異なる
- 通貨記号付与は JSON 側では不可

SQL 側で文字列化しておけば widget 種別に依存しない。ただし数値計算が後段で必要な場合は表示用カラムを別途用意する。

## filter 設計原則

### ウィジェット個別 filter は不可

- ダッシュボード全体に適用される 1 つの filter のみ設定可能
- ウィジェット A だけに「期間 = 今月」、ウィジェット B には「期間 = 先月」のような設計は不可

### ページレベルパラメータで設計

```sql
-- ページパラメータ {{shop_id}} を WHERE 句にバインド
SELECT
  shop_name,
  SUM(revenue) AS total_revenue
FROM mart_sales
WHERE shop_id = {{shop_id}}
GROUP BY shop_name
```

### 個別絞り込みが必要なら別データセット

ウィジェット A 用と B 用で絞り込み条件が違う場合、SQL を分けて 2 つのデータセットを定義する:

```sql
-- データセット A: 今月分
SELECT * FROM mart_sales
WHERE sales_date >= date_trunc('month', current_date)

-- データセット B: 先月分
SELECT * FROM mart_sales
WHERE sales_date >= date_trunc('month', add_months(current_date, -1))
  AND sales_date < date_trunc('month', current_date)
```
