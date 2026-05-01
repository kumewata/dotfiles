---
description: Show tone corpus stats (total pairs, by-context breakdown, latest capture) and GC stale drafts older than 30 days.
---

# Tone Status Command

Tone corpus の状態を確認する。`$ARGUMENTS` でフラグを受け取れる。

## Step 1: 引数を解釈

| 引数              | 動作                                                                   |
| ----------------- | ---------------------------------------------------------------------- |
| （引数なし）      | 統計表示 + drafts/ TTL GC を実行                                       |
| `--gc-dry-run`    | 統計表示 + GC 対象を `[would-gc] ...` の形で列挙するだけ（削除しない） |
| `--rebuild-index` | `index.json` を pairs/ から再構築してから統計表示                      |

## Step 2: 実行

```bash
~/.claude/scripts/tone-status.sh "$ARGUMENTS"
```

## Step 3: 結果をそのまま表示

スクリプトの stdout は人間が読める形式で完結している。**追加の解釈・要約はしない**。出力例:

```text
Tone corpus status
  Total pairs: 4
  By context:  formal=3 / casual=1
  Latest:      2026-04-30T15:10:00+09:00 (formal) https://github.com/foo/bar/pull/42

Drafts: total=1, kept=1, gc=0
```

ペア数が `TONE_PHASE2_THRESHOLD`（既定 10）を超えると、末尾に Phase 2 移行 notice が追記される。出てきた場合はユーザーに通知のうえで「Phase 2 設計を再開しますか？」と一行だけ尋ねる。

## 注意

- TTL は `TONE_DRAFT_TTL_DAYS`（既定 30 日）で上書き可能。スクリプトは frontmatter の `created_at` を見るので、ファイル mtime に依存しない。
- index.json が破損していたら自動で警告を出して再構築する。
