# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a macOS (Apple Silicon) dotfiles repo managed with **Nix Flakes** and **Home Manager**. It declaratively configures the user environment (shell, packages, dotfiles). The username is dynamically resolved from `$USER` at build time via `--impure` flag, so the config works across multiple devices without modification.

## Key Commands

```bash
# Apply configuration changes (defined as shell alias `hms`)
nix run github:nix-community/home-manager/release-25.11 -- switch --impure --flake .#default

# Update flake inputs
nix flake update
```

## Architecture

- `flake.nix` - Flake entrypoint. Targets `aarch64-darwin`, uses nixpkgs unstable + home-manager.
- `home.nix` - Main Home Manager config. Imports all modules from `modules/`. Defines user identity and base packages.
- `modules/` - Modular config split by concern:
  - `packages.nix` - CLI tools installed via Nix (ripgrep, fd, etc.)
  - `shell.nix` - Zsh config with Oh My Zsh, shell aliases, and `initExtra` scripts (mise, gcloud, Java, etc.)
  - `agent-skills.nix` - [agent-skills-nix](https://github.com/Kyure-A/agent-skills-nix) を使い `config/agents/skills/` を `~/.claude/skills/` と `~/.codex/skills/` にデプロイ。`symlink-tree` 構造（rsync）で実ディレクトリとして配置。
- `config/agents/skills/` - Claude Code / OpenAI Codex 共通のスキル定義。agent-skills-nix 経由でデプロイ。
- `.zshrc` - Legacy standalone zsh config (being migrated into `modules/shell.nix`).

## Nix Conventions

- Shell variables in `initExtra` strings must be escaped as `''$VAR` (Nix indented string syntax).
- All package references use `pkgs.<name>` from nixpkgs unstable.
- The flake uses `builtins.getEnv "USER"` with `--impure` to dynamically resolve the username. No per-device edits needed.
- `extraSpecialArgs` passes `username` と `inputs` to all modules.
