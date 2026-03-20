# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a macOS (Apple Silicon) dotfiles repo managed with **Nix Flakes** and **Home Manager**. It declaratively configures the user environment (shell, packages, dotfiles). The username is dynamically resolved from `$USER` at build time via `--impure` flag, so the config works across multiple devices without modification.

## Key Commands

```bash
# Apply configuration changes (defined as shell alias `hms`)
nix run --impure github:nix-community/home-manager/release-25.11 -- switch --impure --flake .#default

# Update flake inputs
nix flake update
```

## Architecture

- `flake.nix` - Flake entrypoint. Targets `aarch64-darwin`, uses nixpkgs unstable + home-manager.
- `home.nix` - Main Home Manager config. Imports all modules from `modules/`. Defines user identity and base packages.
- `modules/` - Modular config split by concern:
  - `packages.nix` - CLI tools installed via Nix (ripgrep, fd, etc.)
  - `shell.nix` - Zsh config with Oh My Zsh, shell aliases, and `initExtra` scripts (mise, gcloud, Java, etc.)
  - `git.nix` - Git の設定（gitignore 等）。
  - `agent-skills.nix` - エージェント関連の統一管理モジュール。[agent-skills-nix](https://github.com/Kyure-A/agent-skills-nix) によるスキルデプロイ（`~/.claude/skills/`, `~/.codex/skills/`）に加え、エージェント定義・コマンド・ルール・スクリプトのデプロイ、Claude Code グローバル設定（`~/.claude/settings.json`）、Codex CLI ルール（`~/.codex/rules/`）も管理。
- `config/agents/skills/` - Claude Code / OpenAI Codex 共通のスキル定義。agent-skills-nix 経由でデプロイ。
- `config/agents/rules/` - Claude Code のグローバルルール。`~/.claude/rules/` にデプロイされ、起動時に常に読み込まれる。スキルの発動トリガー条件を定義。
- `config/agents/definitions/` - エージェント定義。`~/.claude/agents/` にデプロイ。開発ワークフロー用エージェント（planner, architect, code-reviewer, tdd-guide, security-reviewer, doc-updater, python-reviewer, terraform-reviewer）と検索用エージェント（steering-research, doc-search）を含む。
- `config/agents/commands/` - Claude Code のカスタムコマンド。`~/.claude/commands/` にデプロイ。`/orchestrate` コマンドで複数エージェントの sequential pipeline を実行。
- `config/agents/scripts/` - Claude Code 用のヘルパースクリプト。`~/.claude/scripts/` にデプロイ。statusline 表示用スクリプト等を含む。
- `.zshrc` - Legacy standalone zsh config (being migrated into `modules/shell.nix`).

## Nix Conventions

- Shell variables in `initExtra` strings must be escaped as `''$VAR` (Nix indented string syntax).
- All package references use `pkgs.<name>` from nixpkgs unstable.
- The flake uses `builtins.getEnv "USER"` with `--impure` to dynamically resolve the username. No per-device edits needed.
- `extraSpecialArgs` passes `username` と `inputs` to all modules.

## Adding Agents / Commands

エージェント定義やコマンドの追加は2ステップ:

**エージェント定義** (`config/agents/definitions/<name>.md`):
1. ファイル作成。frontmatter: `name`, `description`, `tools`, `model`
2. `modules/agent-skills.nix` の `agentDefinitions` リストに名前を追加

**コマンド** (`config/agents/commands/<name>.md`):
1. ファイル作成。frontmatter: `description` のみ
2. `modules/agent-skills.nix` の `agentCommands` リストに名前を追加

`mkAgentEntries` ヘルパーにより `~/.claude/agents/`・`~/.claude/commands/` に自動デプロイされる。追加後 `hms` で適用。
