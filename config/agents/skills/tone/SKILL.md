---
name: tone
description: |
  Use when the user asks for help drafting a GitHub PR description, a PR review comment, or a Slack post in their own tone (i.e., their personal writing voice). The skill detects the context (formal for PR / review, casual for Slack) and target_type (pr_description, pr_review, slack), drafts the body with an explicit reflection step that avoids verbose, mechanical phrasing, and stages the draft to `~/.local/state/tone/drafts/` via `tone-stage-draft.sh`. The user later runs `/tone-capture <url>` after posting, which pairs the staged draft with the final body to build a corpus for future tone tuning. Trigger especially when the user mentions PR description, PR review comment, Slack post, または「文を書いて」「文面を作って」「自分らしく」「トーン」「tone」.
---

# Tone Skill

GitHub PR description / PR レビューコメント / Slack 投稿のドラフトを生成しつつ、`(draft, final)` ペアコーパス構築のために draft をローカルにステージングする。Phase 1 では capture と編集アシストに専念し、Phase 2（few-shot 注入や style rule 抽出）は corpus が育ってから設計する。

## 1. 使うタイミング

| 状況                                                                                   | context  | target_type      |
| -------------------------------------------------------------------------------------- | -------- | ---------------- |
| GitHub PR の description を書いて欲しい / 更新して欲しい                               | `formal` | `pr_description` |
| GitHub PR にレビューコメントを書いて欲しい（inline / toplevel / submit body どれでも） | `formal` | `pr_review`      |
| GitHub Discussion の本文 / コメント / 返信を書いて欲しい                               | `formal` | `discussion`     |
| Slack に投稿する文面を書いて欲しい（チャンネル投稿、スレッド返信、DM）                 | `casual` | `slack`          |

判別が難しいときはユーザーに 1 問だけ確認する。`context` と `target_type` の組み合わせ制約:

- `formal` → `pr_description` / `pr_review` / `discussion`
- `casual` → `slack` 一択

## 2. 発動しないケース

以下のものは tone corpus を汚すだけなので発動しない:

- 1〜2 行のチャットへの相槌・即返
- コードコメントや commit メッセージ（git skill 担当）
- 議事録、ドキュメント本体、設計メモ（雑多な文書）
- 既存テキストの単純な誤字修正

## 3. 生成プロンプト（自己内省）

draft 生成前に以下を内省する:

1. **冗長さの排除** — 「〜について」「〜となります」「ご確認ください」などの定型句で字数を稼がない。結論を最初に置く。
2. **温度感** — 機械的な丁寧語の連打を避ける。`pr_description` は淡々と、`pr_review` は率直に、`slack` はくだけた口調で短く。
3. **構造の選択** — 箇条書きは 3 つまでを目安。長文での説明が必要なら段落で書く。見出しは `pr_description` にだけ使い、`pr_review` と `slack` では原則使わない。
4. **情報量の取捨** — 読み手が既に知っていることは書かない。意思決定の根拠と影響範囲を優先する。

<!-- PHASE2: inject few-shot examples here from ~/.local/state/tone/pairs/<context>/ -->
<!-- 将来、~/.local/state/tone/pairs/ 配下の最近のペアから類似サンプルを 2-3 件取得して、生成前にコンテキストへ差し込む。Phase 1 ではこのセクションは placeholder のまま。 -->

## 4. Draft staging 手順

draft 本文が固まったら、`tone-stage-draft.sh` に渡してステージングする。

```text
~/.claude/scripts/tone-stage-draft.sh \
  --context <formal|casual> \
  --target-type <pr_description|pr_review|discussion|slack> \
  --target-hint "<元のユーザー依頼を 1 文で要約>" <<'DRAFT'
<draft 本文>
DRAFT
```

スクリプトは成功時に `draft_id` だけを stdout に返す。**この `draft_id` を保持して、ユーザーへの応答末尾の notice に埋める**。

## 5. 出力フォーマット

draft 本文をユーザーに提示したあと、**必ず** 末尾に以下の notice を添える:

```text
📝 staged as <draft_id>. After posting, run /tone-capture <url>
```

Slack の場合は注釈を 1 行追加する:

```text
（Slack の URL は `<workspace>.slack.com/archives/<channel>/p<ts>` 形式の permalink を使う。/tone-capture が MCP 経由で final 本文を取得する。）
```

## 6. 注意

- ステージ先の `~/.local/state/tone/` は tone corpus 専用のローカルディレクトリ。git 管理外で、機微情報を含む可能性がある。
- tone skill は draft を**生成して保存するだけ**。投稿は行わない。投稿はユーザーが手動で行い、その後 `/tone-capture <url>` を叩く。
- 生成途中で「やっぱりやめる」となったら staging は残るが、`/tone-status` 実行時に 30 日 TTL で GC される。
