---
name: index-generator
description: 指定ディレクトリの YAML Front Matter を持つ Markdown ファイルをスキャンして INDEX.md を自動生成するスキル。プロジェクト一覧、タグインデックス、キーワードインデックスを構築し、doc-search エージェントの Level 1 検索を有効化する。
allowed-tools: Read, Write, Glob
---

# index-generator スキル

指定ディレクトリ内の YAML Front Matter を持つドキュメントをスキャンし、INDEX.md を自動生成するスキルです。

## スキルの目的

- YAML Front Matter からメタデータ（title, tags, keywords）を抽出
- タグインデックス・キーワードインデックスを構築した INDEX.md を生成
- doc-search エージェントの Level 1 検索（インデックス参照）を有効化
- ドキュメント数が増えても効率的に検索できる環境を維持

## 使用タイミング

このスキルは以下のタイミングで使用してください：

1. **新規ドキュメント追加時**: 新しいドキュメントをディレクトリに追加した後
2. **ドキュメント更新時**: 既存ドキュメントの Front Matter を更新した後
3. **定期メンテナンス**: インデックスの同期が取れていない可能性があるとき
4. **初期セットアップ**: ディレクトリに初めて INDEX.md を作成するとき

## 実行手順

### ステップ1: 対象ディレクトリを確認

ユーザーに対象ディレクトリを確認する。デフォルトは以下：

```
docs/
.steering/
notes/
.planning/
```

複数ディレクトリの場合、それぞれに個別の INDEX.md を生成する。

### ステップ2: *.md ファイルをスキャン

```
Glob('<target_dir>/**/*.md')
```

以下を除外：
- `INDEX.md` 自体
- `README.md`
- `.git/`, `node_modules/`, `result/`, `.direnv/` 内のファイル

### ステップ3: 各ファイルの Front Matter を抽出

各ファイルを Read ツールで読み込み、YAML Front Matter を抽出する。

**Front Matter 抽出ルール**:
- ファイルの先頭が `---` で始まる場合のみ Front Matter あり（行頭限定・空白不可）
- 先頭の `---` から次の行頭 `---` までが Front Matter ブロック（行頭に空白があるものは終端とみなさない）
- それ以降は本文（処理対象外）

**抽出するフィールド**:
- `title`: ドキュメントタイトル（なければファイル名を使用）
- `tags`: カテゴリタグ（リスト形式 or 文字列。前後の空白を trim・重複を除去して使用）
- `keywords`: 固有名詞（リスト形式 or 文字列。前後の空白を trim・重複を除去して使用）
- `updated_at`: 最終更新日（なければ `created_at` を使用）
- `created_at`: 作成日

**日付のパース規則**:
- フォーマット: `YYYY-MM-DD`（ISO 8601）
- `updated_at` → `created_at` の順で有効な日付を優先
- 両方とも欠落・不正フォーマットの場合: ソートで末尾（最古扱い）として扱い、`Info: {path} の日付が取得できないため末尾に配置します` を表示

**tags / keywords の正規化ルール**:
- 前後の空白を trim する（例: `" Nix "` → `"Nix"`）
- 重複エントリを除去（大文字小文字は区別する）
- リスト形式（`[a, b]`）と単一文字列の両方を受け付ける

**エラーハンドリング**:
- Front Matter がないファイル: スキップし警告を表示（例: `Warning: file.md には Front Matter がありません`）
- `title` がないファイル: ファイル名（拡張子なし）をタイトルとして使用し情報を表示
- `tags`, `keywords` がないファイル: 空として扱う（インデックスに含めない）
- 不正な YAML 構文: スキップし警告を表示（例: `Warning: file.md の Front Matter が不正です`）

### ステップ4: メタデータを集計

抽出したメタデータから以下を構築する：

**プロジェクト一覧**:
- 全ファイルを更新日降順でソート
- `updated_at` がない場合は `created_at` で代替
- 両方とも欠落・不正フォーマットの場合: 末尾（最古扱い）に配置
- 同点の場合はファイルパス昇順

**タグインデックス**:
- `Map<tag, List<{title, path}>>` を構築
- タグ見出しは辞書順昇順（日本語はユニコード順）
- 各タグ内のファイルはタイトル昇順

**キーワードインデックス**:
- `Map<keyword, List<{title, path}>>` を構築
- キーワード見出しは辞書順昇順
- 各キーワード内のファイルはタイトル昇順

### ステップ5: INDEX.md を生成

**0件チェック**: ステップ3でスキップされなかったファイルが0件の場合、INDEX.md を生成せずにステップ6に進む。

Write ツールで INDEX.md を書き込む（既存ファイルは完全上書き）。Write が失敗した場合（権限エラー等）はエラーメッセージを表示して処理を中止する（例: `Error: {path}/INDEX.md への書き込みに失敗しました。ディレクトリの書き込み権限を確認してください`）。

**パス**: `<target_dir>/INDEX.md`

**形式**:

```markdown
# ドキュメントインデックス

最終更新: {YYYY-MM-DD HH:MM UTC}

## プロジェクト一覧（更新日順）

- [{title}]({relative_path_from_INDEX}) - 更新: {updated_at or created_at}
- ...

## タグインデックス

### {tag1}
- [{title}]({relative_path_from_INDEX})
- ...

### {tag2}
- [{title}]({relative_path_from_INDEX})

## キーワードインデックス

### {keyword1}
- [{title}]({relative_path_from_INDEX})
- ...

### {keyword2}
- [{title}]({relative_path_from_INDEX})

## 統計情報

- 総ドキュメント数: {count}
- 総タグ数: {unique_tag_count}
- 総キーワード数: {unique_keyword_count}
- スキップ: Front Matter なし {n1} 件 / YAML 不正 {n2} 件 / 日付不正 {n3} 件
```

**相対パスの記法**:
- INDEX.md から見た相対パスを使用
- 例: `.steering/` の INDEX.md から `20260223-task/design.md` を参照する場合は `20260223-task/design.md`
- サブディレクトリなしの場合は `filename.md` のみ

### ステップ6: 生成完了を報告

以下の情報をユーザーに報告する：

**0件の場合**:
```
対象ディレクトリに Front Matter 付きドキュメントが見つかりませんでした。INDEX.md は生成しません。
スキャン: {total_scanned} 件 / スキップ: Front Matter なし {n1} 件 / YAML 不正 {n2} 件
```

**1件以上の場合**:
```
INDEX.md を生成しました: <target_dir>/INDEX.md

統計:
- 総ドキュメント数: {count}
- 総タグ数: {tag_count}
- 総キーワード数: {keyword_count}
- スキップ: Front Matter なし {n1} 件 / YAML 不正 {n2} 件 / 日付不正 {n3} 件
```

## INDEX.md の例

`.steering/` ディレクトリに3つのプロジェクトがある場合の例：

```markdown
# ドキュメントインデックス

最終更新: 2026-02-23 10:30 UTC

## プロジェクト一覧（更新日順）

- [汎用 YAML Front Matter ツールの実装](20260223-general-frontmatter-tools/requirements.md) - 更新: 2026-02-23
- [index-generator スキルの実装](20260223-index-generator/requirements.md) - 更新: 2026-02-23
- [Nix Flakes のマルチデバイス対応](20260208-multi-device-support/requirements.md) - 更新: 2026-02-08

## タグインデックス

### アーキテクチャ
- [frontmatter スキルと doc-search エージェントの設計](20260223-general-frontmatter-tools/design.md)
- [index-generator スキル設計](20260223-index-generator/design.md)

### 実装
- [汎用 YAML Front Matter ツール - 実装タスクリスト](20260223-general-frontmatter-tools/tasklist.md)
- [index-generator スキル - 実装タスクリスト](20260223-index-generator/tasklist.md)

### 設計
- [frontmatter スキルと doc-search エージェントの設計](20260223-general-frontmatter-tools/design.md)
- [index-generator スキル設計](20260223-index-generator/design.md)

## キーワードインデックス

### INDEX.md
- [index-generator スキルの実装](20260223-index-generator/requirements.md)
- [index-generator スキル設計](20260223-index-generator/design.md)

### Nix
- [Nix Flakes のマルチデバイス対応 - 要件](20260208-multi-device-support/requirements.md)

### frontmatter
- [汎用 YAML Front Matter ツールの実装](20260223-general-frontmatter-tools/requirements.md)
- [frontmatter スキルと doc-search エージェントの設計](20260223-general-frontmatter-tools/design.md)

## 統計情報

- 総ドキュメント数: 9
- 総タグ数: 12
- 総キーワード数: 8
```

## エラーハンドリング詳細

| 状況 | 対処 |
|------|------|
| Front Matter なし | スキップ（n1 カウント） + `Warning: {path} には Front Matter がありません` |
| title なし | ファイル名（拡張子なし）をタイトルとして使用 + `Info: {path} の title がないため、ファイル名を使用します` |
| tags なし | タグインデックスには含めない |
| keywords なし | キーワードインデックスには含めない |
| 不正な YAML | スキップ（n2 カウント） + `Warning: {path} の Front Matter が不正です` |
| 日付欠落・不正フォーマット | 末尾（最古扱い）でソート（n3 カウント） + `Info: {path} の日付が取得できないため末尾に配置します` |
| 対象ドキュメント0件（n1+n2件のみ） | INDEX.md を生成しない + スキャン結果を報告 |
| Write 失敗 | 処理を中止 + `Error: {path}/INDEX.md への書き込みに失敗しました。ディレクトリの書き込み権限を確認してください` |

## チェックリスト

生成前に確認：

- [ ] 対象ディレクトリが存在するか？
- [ ] 対象ディレクトリに *.md ファイルがあるか？
- [ ] 書き込み権限があるか？

生成後に確認：

- [ ] INDEX.md が生成されたか？
- [ ] プロジェクト一覧に全ドキュメントが含まれているか？
- [ ] タグインデックスが辞書順になっているか？
- [ ] キーワードインデックスが辞書順になっているか？
- [ ] 最終更新日が記録されているか？
- [ ] 統計情報が正しいか？

## doc-search エージェントとの連携

このスキルで生成した INDEX.md は、doc-search エージェントの Level 1 検索で参照されます。

**検索フロー（doc-search）**:
1. **Level 1**: `{directory}/INDEX.md` を参照（このスキルで生成したファイル）
2. **Level 2**: YAML Front Matter 検索（Level 1 でマッチしない場合）
3. **Level 3**: 全文検索（Level 2 でマッチしない場合）

INDEX.md が存在することで Level 1 検索が有効になり、検索が高速化されます。
