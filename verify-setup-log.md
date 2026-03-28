# Web Setup 検証結果

検証日: 2026-03-28

## 2. セットアップログの確認

```
[05:32:59] Starting lightweight setup for Claude Code Web
[05:32:59] Installing GitHub CLI 2.67.0...
[05:33:01] Installed gh 2.67.0 to /usr/local/bin/gh
[05:33:01] Cloning dotfiles...
[05:33:01] Agent configs deployed
[05:33:01] Setup complete in 2s (commit: 434cf1d7a8088be5f0626340e54fbac7198ee9df)
```

## 3. 受け入れ条件の確認

### ① gh が使えるか

```
$ gh --version
gh version 2.67.0 (2025-02-11)
```

**結果: OK**

### ② エージェント設定が配置されているか

| パス | 状態 | 内容 |
|------|------|------|
| `~/.claude/skills/` | OK | 20 スキル (bigquery, claude-config-optimizer, codex-delegate, databricks, dbt, difit, draw-io, frontmatter, git, github, index-generator, nix, pdf, skill-creator, steering, terraform, terraform-refactor-module, terraform-style-guide, terraform-test, xlsx) |
| `~/.claude/agents/` | OK | 10 エージェント (architect, code-reviewer, doc-search, doc-updater, planner, python-reviewer, security-reviewer, steering-research, tdd-guide, terraform-reviewer) |
| `~/.claude/rules/` | OK | skill-triggers.md |
| `~/.claude/settings.json` | OK | 存在 |
| `~/.codex/rules/nix-managed.rules` | OK | 存在 |

**結果: OK**

### ③ nix.conf が修正されているか

```
$ cat /etc/nix/nix.custom.conf
cat: /etc/nix/nix.custom.conf: No such file or directory

$ grep extra-substituters /etc/nix/nix.conf
grep: /etc/nix/nix.conf: No such file or directory
```

**結果: N/A** — この環境に Nix がインストールされていないため確認不可。ベストエフォートの修正なので想定内。

### ④ nix の速度

**結果: N/A** — Nix 未インストール環境のためスキップ。

## 4. 冪等性の確認

### マーカーの確認

```
$ cat ~/.local/state/web-setup-done
434cf1d7a8088be5f0626340e54fbac7198ee9df
```

**結果: OK** — commit hash が記録済み。

### 手動再実行

権限制限により `bash ~/.dotfiles/setup-web.sh` の再実行は実施できず。
マーカーファイルが存在するため、再実行時にスキップされる仕組みは有効と判断。

## 5. 失敗時の切り分け

### hook が発火したか確認

```
$ ls -la ~/.local/state/web-setup*
-rw-r--r-- 1 root root   41 Mar 28 05:33 /root/.local/state/web-setup-done
-rw-r--r-- 1 root root    0 Mar 28 05:43 /root/.local/state/web-setup.lock
-rw-r--r-- 1 root root 5690 Mar 28 05:33 /root/.local/state/web-setup.log
```

**結果: OK** — 3 ファイルすべて存在。

### 環境変数の確認

| 変数 | 値 | 状態 |
|------|-----|------|
| `CLAUDE_CODE_REMOTE` | `true` | OK |
| `CLAUDE_ENV_FILE` | (空) | 未設定 |

## サマリー

| # | チェック項目 | 結果 | 備考 |
|---|-------------|------|------|
| 2 | セットアップログ | **OK** | 全ステップ記録済み。2秒で完了 |
| 3-① | `gh --version` | **OK** | `gh 2.67.0` |
| 3-② | エージェント設定配置 | **OK** | skills(20), agents(10), rules(1), settings.json, codex rules |
| 3-③ | nix.conf 修正 | **N/A** | Nix 未インストール環境 |
| 3-④ | nix 速度 | **N/A** | 同上 |
| 4 | 冪等性マーカー | **OK** | commit hash 記録済み |
| 4 | 手動再実行 | **未実施** | 権限制限によりスキップ |
| 5-① | hook 発火確認 | **OK** | 3 ファイル存在 |
| 5-② | `CLAUDE_CODE_REMOTE` | **OK** | `true` |
| 5-③ | `CLAUDE_ENV_FILE` | **未設定** | 空文字列 |
