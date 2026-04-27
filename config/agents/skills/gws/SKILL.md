---
name: gws
description: |
  Google Workspace CLI (`gws`) を使って Google スプレッドシート・ドキュメント・スライドを参照・編集するためのスキル。
  Use when:
  - ユーザーが Google Sheets / Docs / Slides の URL（`docs.google.com/spreadsheets/d/...` / `docs.google.com/document/d/...` / `docs.google.com/presentation/d/...`）を貼り付けた、または ID を渡したとき
  - 「このスプレッドシートを要約して」「A 列の値を見せて」「タブ X の中身は？」「このセルを更新して」「行を追記して」等、Sheets の読み書きを依頼されたとき
  - 「この Doc をレビューして」「この Google ドキュメントの本文を Markdown で」等、Docs の本文が欲しいとき
  - 「このスライドのタイトル一覧」「5 枚目の内容」等、Google Slides の内容参照を依頼されたとき
  - URL は無いが特定の Google Workspace ファイル（Sheets/Docs/Slides）を名前で探す必要があるとき
  - `gws` コマンドを実行する、または出力を解釈するとき
  Do NOT use when:
  - Google API を Python / Node SDK から直接呼ぶ場合（本スキルは CLI 実行が前提）
  - ユーザーがブラウザ操作を希望している場合
  - 汎用の Google Drive 管理（権限、共有、フォルダ構成）が主目的で Workspace ファイル内容は触らないとき
---

# gws: Google Workspace CLI 操作スキル

`gws` は Google Workspace API をまとめて叩ける Rust 製 CLI（mise shim で導入済み）。
デフォルトでは **JSON を返す**ため、用途に応じて `--format` / `--page-all` を切り替える。

## 0. 前提チェック

認証失敗は exit 2（`Auth error`）で出る。迷ったら最初に状態確認する。

```bash
gws auth status      # user / scopes / token_valid を確認
gws auth login       # 失効していたら再ログイン（ブラウザが開く）
```

代表スコープ（最小権限を選ぶ指針）:

| 用途 | 読み取り専用 | 書き込み込み |
| --- | --- | --- |
| Sheets | `spreadsheets.readonly` | `spreadsheets` |
| Docs | `documents.readonly` + `drive.readonly`（export 用） | `documents` + `drive` |
| Slides | `presentations.readonly` + `drive.readonly` | `presentations` + `drive` |
| Drive 検索/export | `drive.readonly` | `drive` |

参照だけが目的なら `.readonly` スコープでログインする方が安全。

## 1. URL から ID を取り出す

Google Workspace の URL は `/d/<ID>/` の形でドキュメント ID を含む。
処理前の第一歩が ID 抽出。

| サービス | URL パターン | 抽出対象 |
| --- | --- | --- |
| Sheets | `https://docs.google.com/spreadsheets/d/<ID>/edit` | spreadsheetId |
| Docs | `https://docs.google.com/document/d/<ID>/edit` | documentId |
| Slides | `https://docs.google.com/presentation/d/<ID>/edit` | presentationId |
| Drive file | `https://drive.google.com/file/d/<ID>/view` | fileId |

`#gid=123` は Sheets 内のシート（タブ）の内部 ID。range 指定ではシート **名** (`'Sheet1'!A1:B2`) を使う方が確実。

## 2. Sheets（読み取りが主用途、書き込みもあり）

### 2.1 読み取り — `+read` ヘルパーが最速

```bash
# 範囲指定（人間向けには table、プログラム処理なら csv/json）
gws sheets +read \
  --spreadsheet <SPREADSHEET_ID> \
  --range "Sheet1!A1:D20" \
  --format table

# シート全体を CSV で
gws sheets +read --spreadsheet <ID> --range Sheet1 --format csv
```

シート名にスペースや日本語が含まれる場合は引用符で囲む: `"'売上 2026'!A:C"`。

### 2.2 メタデータ取得（シート名・タブ ID を知る）

```bash
gws sheets spreadsheets get \
  --params '{"spreadsheetId": "<ID>", "fields": "sheets.properties"}' \
  --format json
```

`sheets.properties.title` / `sheetId` / `gridProperties.rowCount` が取れる。
URL の `#gid=` は `sheetId` に対応。

### 2.3 追記 — `+append` ヘルパーの**重要な制限**

```bash
gws sheets +append --spreadsheet <ID> --values 'Alice,100,true'
gws sheets +append --spreadsheet <ID> --json-values '[["a","b"],["c","d"]]'
```

**注意**: `+append` ヘルパーはタブ指定できず、常にデフォルト（先頭）シートの `A1` テーブルに追記する（内部的に `values/A1:append` を呼ぶ）。複数タブを持つスプレッドシートで意図したタブを指定したい場合は raw API を使う。

```bash
# 明示的にタブと列範囲を指定して追記
gws sheets spreadsheets values append \
  --params '{
    "spreadsheetId": "<ID>",
    "range": "'"'"'売上 2026'"'"'!A:C",
    "valueInputOption": "USER_ENTERED"
  }' \
  --json '{"values": [["2026-04-21", "foo", 100]]}' \
  --dry-run
```

### 2.4 既存セルの更新（raw API）

書き込みは **必ず `--dry-run` で URL・ペイロードを確認してから本番実行** する。

```bash
gws sheets spreadsheets values update \
  --params '{
    "spreadsheetId": "<ID>",
    "range": "Sheet1!B2:B4",
    "valueInputOption": "USER_ENTERED"
  }' \
  --json '{"range": "Sheet1!B2:B4", "values": [["foo"],["bar"],["baz"]]}' \
  --dry-run
```

- `valueInputOption`: `USER_ENTERED`（数式・日付を解釈）/ `RAW`（文字列そのまま）
- 複数範囲を一括更新 → `spreadsheets values batchUpdate`

## 3. Docs（参照）

### 3.1 本文テキストを取る（推奨: Drive export）

`docs documents get` の JSON は構造が深く扱いづらい。**LLM/人間が読むためのテキストが欲しいなら Drive の `files.export` が圧倒的に楽**。ただし **export は 10 MB 上限**（超える場合は `files.get alt=media` で分割ダウンロード、または範囲を絞る）。

```bash
# Markdown（見出し・箇条書きが保持される）
gws drive files export \
  --params '{"fileId": "<DOC_ID>", "mimeType": "text/markdown"}' \
  --output doc.md

# プレーンテキスト
gws drive files export \
  --params '{"fileId": "<DOC_ID>", "mimeType": "text/plain"}' \
  --output doc.txt
```

`--output` を付けると標準出力ではなくファイルに書き出す（バイナリ安全）。

### 3.2 構造を JSON で扱う — **タブ対応を忘れない**

Google Docs は複数タブを持ち得る。素の `documents get` は **最初のタブしか `body` に入れない**。全タブを取るには `includeTabsContent: true` が必要。

```bash
# 全タブ含めて取得
gws docs documents get \
  --params '{"documentId": "<DOC_ID>", "includeTabsContent": true}' \
  --format json
```

返ってくる JSON の主要パス:

- `tabs[].documentTab.body.content[]` — 各タブの本文（`includeTabsContent=true` 時）
- `tabs[].documentTab.namedStyles` — タブごとの見出しスタイル
- `body.content[]` — **レガシー**。最初のタブのみ。`includeTabsContent=false` or 未指定時のみ有効
- `*.paragraph.elements[].textRun.content` — 生テキスト

先に export で Markdown 化し、構造やコメント・スタイルが必要な場合だけ JSON を見る方が効率的。

### 3.3 末尾に追記（軽い編集）

```bash
gws docs +write --document <DOC_ID> --text 'Hello, world!'
```

書式付き編集が必要なら `documents batchUpdate`（リクエスト本体は Docs API の `Request` 配列）。本番編集前に **`documents get` で `revisionId` を取り**、`batchUpdate` の `writeControl.requiredRevisionId` に渡すと他ユーザーの同時編集を検出できる。

## 4. Slides（参照）

### 4.1 メタデータ・構造

```bash
gws slides presentations get \
  --params '{"presentationId": "<PRES_ID>"}' \
  --format json
```

主要パス:

- `slides[]` — スライド一覧（各スライドは `pageElements[]` を持つ）
- `slides[].objectId` — スライド（ページ）の ID
- `slides[].pageElements[].objectId` — テキスト枠・図形の ID（編集時に必要）
- `slides[].pageElements[].shape.text.textElements[].textRun.content` — テキスト本体

### 4.2 テキスト一括抽出（推奨: Drive export、10 MB 上限）

```bash
gws drive files export \
  --params '{"fileId": "<PRES_ID>", "mimeType": "text/plain"}' \
  --output slides.txt

# PDF で保存
gws drive files export \
  --params '{"fileId": "<PRES_ID>", "mimeType": "application/pdf"}' \
  --output slides.pdf
```

### 4.3 個別スライドの取得

```bash
gws slides presentations pages get \
  --params '{"presentationId": "<PRES_ID>", "pageObjectId": "<SLIDE_ID>"}'
```

サムネイル URL は `pages getThumbnail`。

### 4.4 編集時の注意

`presentations batchUpdate` の `replaceAllText` は **プレゼン全体** に対して文字列置換する。特定スライドの 1 要素だけ変えたいときに使うと事故る。推奨は:

- 対象 shape の `objectId` を `presentations.get` で特定
- `deleteText` + `insertText` を組み合わせて **その shape にだけ** 変更を適用
- `replaceAllText` を使う場合は `pageObjectIds` を指定して影響範囲を絞る
- 本番前に必ず `--dry-run` で送信ペイロードと URL を確認

## 5. Drive（補助: ファイル検索・メタデータ）

URL が不明で「○○という名前のシートを探したい」ときに使う。

```bash
# 名前と種類で検索（Sheets のみ）
gws drive files list \
  --params '{
    "q": "name contains '\''売上'\'' and mimeType = '\''application/vnd.google-apps.spreadsheet'\''",
    "fields": "files(id,name,modifiedTime,webViewLink)",
    "pageSize": 20
  }' \
  --format table

# 大量件数は --page-all で NDJSON 出力（1 行 1 ページ）
gws drive files list --params '{"pageSize": 100}' --page-all --page-limit 5
```

主要 MIME type:

| 種類 | mimeType |
| --- | --- |
| Sheets | `application/vnd.google-apps.spreadsheet` |
| Docs | `application/vnd.google-apps.document` |
| Slides | `application/vnd.google-apps.presentation` |
| Folder | `application/vnd.google-apps.folder` |

## 6. 共通 Tips

### 6.1 出力フォーマット

`--format` は全コマンド共通。`json`（デフォルト）/ `table`（人間向け）/ `csv`（パイプ向け）/ `yaml`。用途で選ぶ。

### 6.2 書き込み系は `--dry-run` を先に

`*Update`, `+append`, `+write`, `values.update/append` 等は `--dry-run` で送信先 URL とペイロードを **API を叩かずに** 確認できる。破壊前に必ず 1 回流す。

### 6.3 `schema` でパラメータを調べる

API 引数が分からなければ discovery を引く。

```bash
gws schema sheets.spreadsheets.values.update
gws schema docs.documents.get --resolve-refs
```

### 6.4 ページング

`list` 系は `--page-all` で NDJSON 自動ページング。デフォルト 10 ページ上限。大量取得が必要なら `--page-limit 50` 等。

### 6.5 エラー対処

- exit 2（Auth）→ `gws auth status` → 必要なら `gws auth login`
- exit 3（Validation）→ `--params` / `--json` の JSON 構造を見直す。`gws schema ...` で期待形を確認
- exit 1（API error）→ stderr のメッセージを読む。権限・ID 不正・quota が多い

## 7. 典型ワークフロー

**「このスプレッドシートの A 列を読み上げて」と URL だけ渡された場合**:

1. URL から spreadsheetId を抽出
2. シート構成を把握:
   ```bash
   gws sheets spreadsheets get \
     --params '{"spreadsheetId": "<ID>", "fields": "sheets.properties.title"}'
   ```
3. **発見したタイトル** を使って読む（`Sheet1` 決め打ちしない）:
   ```bash
   gws sheets +read --spreadsheet <ID> --range "'<SHEET_TITLE>'!A:A" --format csv
   ```

**「この Doc をレビューして」と URL だけ渡された場合**:

1. URL から documentId を抽出
2. Markdown で取得（export は 10 MB 上限、超えたら範囲を絞る）:
   ```bash
   gws drive files export \
     --params '{"fileId": "<DOC_ID>", "mimeType": "text/markdown"}' \
     --output /tmp/doc.md
   ```
3. 書き出したファイルをローカルから読む。構造やコメントまで必要なら `docs documents get --params '{"documentId": "<ID>", "includeTabsContent": true}'` も併用

**「このスライドの 5 枚目のタイトルを変えて」と言われた場合**:

1. URL から presentationId を抽出
2. `slides presentations get` で `slides[4].objectId`（スライド）と対象タイトルの `pageElements[].objectId`（shape）を特定
3. `slides presentations batchUpdate` の JSON を組み立てる（プレゼン全体置換ではなく shape 限定の `deleteText` + `insertText`、または `pageObjectIds` を絞った `replaceAllText`）
4. **`--dry-run` で送信ペイロードを確認 → ユーザーに見せて承認 → 本番実行**
