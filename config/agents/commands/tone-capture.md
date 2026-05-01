---
description: Capture the (draft, final) pair for a posted PR description / PR review comment / Slack message and save it under ~/.local/state/tone/pairs/.
---

# Tone Capture Command

Capture a posted final and pair it with a previously staged draft. Argument: `$ARGUMENTS` is the URL of the post.

## Step 1: URL の判別

`$ARGUMENTS` を URL として解釈する。引数が空なら、ユーザーに URL を尋ねて中断する。

サポートする URL パターン:

| パターン                                                            | 種別                       |
| ------------------------------------------------------------------- | -------------------------- |
| `https://github.com/<owner>/<repo>/pull/<n>`                        | PR description             |
| `https://github.com/<owner>/<repo>/pull/<n>#discussion_r<id>`       | PR inline review comment   |
| `https://github.com/<owner>/<repo>/pull/<n>#issuecomment-<id>`      | PR toplevel issue comment  |
| `https://github.com/<owner>/<repo>/pull/<n>#pullrequestreview-<id>` | PR review submit body      |
| `https://<workspace>.slack.com/archives/<channel>/p<ts>`            | Slack permalink            |

これ以外の URL は `tone-capture.sh` 側で exit 2 となる。エラーメッセージをそのままユーザーに返す。

## Step 2: 実行

### GitHub URL の場合

PR description / inline review / toplevel issue comment のいずれの URL でも、内部で `gh api` で final body を取得する。

```bash
~/.claude/scripts/tone-capture.sh "<url>"
```

### Slack URL の場合

`tone-capture.sh` は Slack URL に対して `--final-stdin` を要求する。Slack MCP ツール（`mcp__claude_ai_Slack__slack_read_channel` または `mcp__claude_ai_Slack__slack_read_thread`）で final 本文を取得し、heredoc で stdin に流す。

1. URL から `channel` と `ts` を抽出する。`?thread_ts=...` を含む URL はスレッド返信なので `slack_read_thread` を使う。それ以外は `slack_read_channel` でチャンネルから対象メッセージを 1 件取得する。
2. 取得した本文を `--final-stdin` 付きで渡す:

   ```bash
   ~/.claude/scripts/tone-capture.sh "<url>" --final-stdin <<'FINAL'
   <slack_message_body>
   FINAL
   ```

## Step 3: 終了コードに応じた応答

| Exit code | 意味                                              | 応答                                                                                                                                                                                                                        |
| --------- | ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0         | 成功                                              | スクリプトが stdout に出した `✅ Pair saved: ...` をそのまま表示                                                                                                                                                            |
| 2         | 引数エラー / 未対応 URL / unknown draft_id        | エラーメッセージを表示し、ユーザーに URL を再確認してもらう                                                                                                                                                                 |
| 3         | candidates ambiguous（複数の draft が候補に該当） | stderr に出力された候補一覧をユーザーに見せ、どの `draft_id` を使うか選んでもらう。選択された ID で `~/.claude/scripts/tone-capture.sh "<url>" --draft-id <id>` を再実行する（Slack URL の場合は `--final-stdin` も再付与） |
| 4         | gh fetch 失敗                                     | gh の認証 / ネットワーク / URL のいずれかをユーザーに確認                                                                                                                                                                   |
| その他    | 想定外                                            | エラーメッセージを表示                                                                                                                                                                                                      |

## Step 4: 結果報告

成功時は `tone-capture.sh` の stdout 行（`✅ Pair saved: pairs/<context>/<date>-<slug>.md (edit_ratio: <ratio>)`）をそのままユーザーに返す。**追加の解説や要約はしない**（ユーザーは結果を一目で読める）。

## 注意

- 同じ `<url>` で再実行すると pair file は上書きされる（編集後の最新版が正解）。
- 対応する staged draft が見つからない場合は orphan モード（draft 部分は `(orphan capture)`、edit_ratio は 1.0）で final だけ保存する。これも有効なコーパス資産。
- `~/.local/state/tone/` は agent ツール（Read/Write）の `additionalDirectories` に含まれていない。診断のために pair を読む必要があるときは `~/.claude/scripts/tone-status.sh` を使う、または `additionalDirectories` への追加を検討する。
