---
name: difit
description: |
  Git diff viewer with browser-based UI. Use when:
  - Reviewing code changes before commit or PR
  - Comparing branches or commits visually
  - User mentions "difit", "diff viewer", or asks to review changes in browser
---

# difit Skill

ローカルで Git 差分をブラウザ上に見やすく表示するツール。
Node.js 21+ が必要。`npx difit` で実行（初回以降はキャッシュ利用）。

## 1. 基本コマンド

| 用途               | コマンド                        |
| ------------------ | ------------------------------- |
| 最新コミットの差分 | `npx difit`                     |
| 未コミット変更     | `npx difit .`                   |
| ステージ済み変更   | `npx difit staged`              |
| 特定コミット       | `npx difit <commit-hash>`       |
| ブランチ比較       | `npx difit <branch1> <branch2>` |
| GitHub PR          | `npx difit --pr <PR-URL>`       |

## 2. 主要オプション

| オプション  | デフォルト | 説明                               |
| ----------- | ---------- | ---------------------------------- |
| `--mode`    | `split`    | 表示モード（`split` / `unified`）  |
| `--tui`     | -          | ブラウザを開かずターミナル内で表示 |
| `--port`    | `4966`     | サーバーポート番号                 |
| `--no-open` | -          | ブラウザの自動起動を抑制           |
| `--clean`   | -          | コメント履歴をクリア               |

## 3. PR レビュー

GitHub PR の差分を表示するには `gh` CLI の認証が必要:

```sh
# gh CLI でログイン済みであればそのまま使える
npx difit --pr https://github.com/owner/repo/pull/123

# GH_TOKEN 環境変数でも認証可能
GH_TOKEN=xxx npx difit --pr https://github.com/owner/repo/pull/123
```

## 4. 典型的なワークフロー

### コミット前のセルフレビュー

```sh
# 未コミット変更をブラウザで確認
npx difit .

# ステージ済みの変更のみ確認
npx difit staged
```

### ブランチ比較（マージ前の確認）

```sh
npx difit feature-branch main
```
