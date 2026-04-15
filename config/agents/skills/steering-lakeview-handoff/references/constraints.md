# Lakeview Widget Constraints (設計時早見表)

`steering-lakeview-handoff` スキルの Step 2 で読み、ウィジェット種別ごとの制約を **要件・データセット定義に反映** するための早見表。

## ウィジェット型別の非対応機能と代替策

| Widget  | 非対応機能                                  | 代替策                                                                                                               |
| ------- | ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| bar     | 軸カスタムソート / データラベル / Marimekko | SQL `ORDER BY` で並び制御、title で補足表示                                                                          |
| line    | セグメント連結 (gap bridging)               | SQL 側で `COALESCE(col, 0)` による NULL 埋め                                                                         |
| table   | encoding `type` 省略 (列が消える)           | `quantitative` / `nominal` / `temporal` / `ordinal` を明示。ただし新規追加カラムでは type 省略の方が安全なケースあり |
| pivot   | セル内条件付き書式 / 小計行                 | SQL で `UNION ALL` による小計行展開                                                                                  |
| counter | 複数値の並列表示                            | counter を複数配置 (1 widget = 1 KPI)                                                                                |
| pie     | 10+ カテゴリ                                | SQL で TOP N + "その他" に集約                                                                                       |

## 共通制約

| 項目            | 制約                                           | 対処                                                |
| --------------- | ---------------------------------------------- | --------------------------------------------------- |
| encoding `type` | 省略すると空欄バグ                             | 全ての encoding に `type` を明示                    |
| NULL 表示       | JSON 側で NULL 制御不可                        | SQL 側で `COALESCE(col, '—')`                       |
| 数値整形        | JSON `numberFormat` は制限あり                 | SQL 側で `FORMAT_NUMBER(val, '#,##0')`              |
| JSON サイズ     | UI 貼り付け上限 約 30KB (超過でサイレント切捨) | `databricks lakeview update <ID> --json @file.json` |
| filter 粒度     | ウィジェット単位の fine-grained 制御不可       | ページレベルパラメータで設計                        |

## 設計時のチェックリスト

`design.md` のクエリ設計・データセット仕様セクションで、以下が反映されているか確認する:

- [ ] 数値カラムは `FORMAT_NUMBER` 適用済み
- [ ] NULL を表示する箇所は `COALESCE(col, '—')` 済み
- [ ] bar/line/pie で並びが必要なら `ORDER BY` で SQL 側制御
- [ ] line で連続性が必要なら NULL 行を `COALESCE` で埋める
- [ ] pivot で小計が必要なら `UNION ALL` で行展開
- [ ] filter はページレベルパラメータで設計し、ウィジェット個別フィルタを要件としない
- [ ] 想定 JSON サイズが 30KB を超える可能性があれば、デプロイ手順を tasklist に明記

## 出典

このリストは実プロジェクトのダッシュボード開発セッションで踏んだ pitfall に基づく。新しい pitfall を発見した場合はこのファイルと Genie Code 側 `lakeview-pitfalls` SKILL.md の両方を更新すること。
