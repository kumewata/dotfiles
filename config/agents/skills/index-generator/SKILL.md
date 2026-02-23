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
- ファイルの先頭が `---` で始まる場合のみ Front Matter あり
- 先頭の `---` から次の `---` までが Front Matter ブロック
- それ以降は本文（処理対象外）

**抽出するフィールド**:
- `title`: ドキュメントタイトル（なければファイル名を使用）
- `tags`: カテゴリタグ（リスト）
- `keywords`: 固有名詞（リスト）
- `updated_at`: 最終更新日（なければ `created_at` を使用）
- `created_at`: 作成日

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

Write ツールで INDEX.md を書き込む（既存ファイルは完全上書き）。

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
```

**相対パスの記法**:
- INDEX.md から見た相対パスを使用
- 例: `.steering/` の INDEX.md から `20260223-task/design.md` を参照する場合は `20260223-task/design.md`
- サブディレクトリなしの場合は `filename.md` のみ

### ステップ6: 生成完了を報告

以下の情報をユーザーに報告する：

```
INDEX.md を生成しました: <target_dir>/INDEX.md

統計:
- 総ドキュメント数: {count}
- 総タグ数: {tag_count}
- 総キーワード数: {keyword_count}
- スキップしたファイル数: {skip_count}（Front Matter なし）
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
| Front Matter なし | スキップ + `Warning: {path} には Front Matter がありません` |
| title なし | ファイル名をタイトルとして使用 + `Info: {path} の title がないため、ファイル名を使用します` |
| tags なし | タグインデックスには含めない |
| keywords なし | キーワードインデックスには含めない |
| 不正な YAML | スキップ + `Warning: {path} の Front Matter が不正です` |
| 対象ドキュメント0件 | INDEX.md を生成しない + `対象ディレクトリに Front Matter 付きドキュメントが見つかりませんでした` |

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
