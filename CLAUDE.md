# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a macOS (Apple Silicon) dotfiles repo managed with **Nix Flakes** and **Home Manager**. It declaratively configures the user environment (shell, packages, dotfiles) for the user `kumewataru`.

## Key Commands

```bash
# Apply configuration changes (defined as shell alias `hms`)
nix run github:nix-community/home-manager/release-25.11 -- switch --flake .#kumewataru

# Update flake inputs
nix flake update
```

## Architecture

- `flake.nix` - Flake entrypoint. Targets `aarch64-darwin`, uses nixpkgs unstable + home-manager.
- `home.nix` - Main Home Manager config. Imports all modules from `modules/`. Defines user identity and base packages.
- `modules/` - Modular config split by concern:
  - `packages.nix` - CLI tools installed via Nix (ripgrep, fd, etc.)
  - `shell.nix` - Zsh config with Oh My Zsh, shell aliases, and `initExtra` scripts (mise, gcloud, Java, etc.)
  - `claude-skills.nix` - Symlinks `config/agents/skills/` to `~/.claude/skills` for Claude Code skill integration.
- `config/agents/skills/` - Claude Code skill definitions deployed via Home Manager.
- `.zshrc` - Legacy standalone zsh config (being migrated into `modules/shell.nix`).

## Nix Conventions

- Shell variables in `initExtra` strings must be escaped as `''$VAR` (Nix indented string syntax).
- All package references use `pkgs.<name>` from nixpkgs unstable.
- The flake has a single homeConfiguration output for `kumewataru`.
