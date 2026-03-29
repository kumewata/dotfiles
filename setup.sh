#!/usr/bin/env bash
# setup.sh — Claude Code / Codex エージェント設定のデプロイスクリプト
#
# 動作:
#   1. CLI ツール (gh, codex) をインストール
#   2. Nix のインストールを試行
#   3. Nix が使える場合 → home-manager switch で正式デプロイ
#   4. Nix が使えない場合 → シンボリックリンクでフォールバックデプロイ
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTS_DIR="${DOTFILES_DIR}/config/agents"

# ホームディレクトリの検出
if [[ -n "${HOME:-}" ]]; then
  HOME_DIR="$HOME"
elif [[ "$(uname)" == "Darwin" ]]; then
  HOME_DIR="/Users/$(whoami)"
else
  HOME_DIR="/home/$(whoami)"
fi

echo "==> Deploying agent configs from ${DOTFILES_DIR}"
echo "    Home: ${HOME_DIR}"

# ════════════════════════════════════════════════════════════════
# Phase 1: CLI ツールのインストール
# ════════════════════════════════════════════════════════════════

# GitHub CLI (gh)
if ! command -v gh &>/dev/null; then
  echo "==> Installing GitHub CLI (gh)..."
  GH_VERSION="2.67.0"
  OS="$(uname -s)"
  ARCH="$(uname -m)"
  case "${OS}:${ARCH}" in
    Darwin:x86_64) GH_ARCH="macOS_amd64" ;;
    Darwin:arm64) GH_ARCH="macOS_arm64" ;;
    Linux:x86_64) GH_ARCH="linux_amd64" ;;
    Linux:aarch64) GH_ARCH="linux_arm64" ;;
    *)
      echo "    WARN: Unsupported platform ${OS}/${ARCH}, skipping gh install"
      GH_ARCH=""
      ;;
  esac
  if [[ -n "${GH_ARCH:-}" ]]; then
    GH_URL="https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_${GH_ARCH}.tar.gz"
    TMP_GH="$(mktemp -d)"
    if curl -fsSL "$GH_URL" -o "${TMP_GH}/gh.tar.gz" 2>/dev/null; then
      tar -xzf "${TMP_GH}/gh.tar.gz" -C "$TMP_GH"
      if [[ -w /usr/local/bin ]]; then
        cp "${TMP_GH}/gh_${GH_VERSION}_${GH_ARCH}/bin/gh" /usr/local/bin/gh
        echo "    Installed gh ${GH_VERSION} to /usr/local/bin/gh"
      else
        mkdir -p "${HOME_DIR}/bin"
        cp "${TMP_GH}/gh_${GH_VERSION}_${GH_ARCH}/bin/gh" "${HOME_DIR}/bin/gh"
        export PATH="${HOME_DIR}/bin:$PATH"
        echo "    Installed gh ${GH_VERSION} to ${HOME_DIR}/bin/gh"
      fi
    else
      echo "    WARN: Failed to download gh CLI (network may be restricted)"
    fi
    rm -rf "$TMP_GH"
  fi
else
  echo "==> gh already installed: $(gh --version | head -1)"
fi

# OpenAI Codex CLI
if command -v npm &>/dev/null; then
  if ! command -v codex &>/dev/null && ! npm list -g @openai/codex &>/dev/null 2>&1; then
    echo "==> Installing OpenAI Codex CLI..."
    if npm install -g @openai/codex 2>/dev/null; then
      echo "    Installed codex CLI: $(codex --version 2>/dev/null || echo 'ok')"
    else
      echo "    WARN: Failed to install codex CLI (try: npx @openai/codex)"
    fi
  else
    echo "==> codex CLI already available"
  fi
else
  echo "==> WARN: npm not found, skipping codex CLI install"
fi

# ════════════════════════════════════════════════════════════════
# Phase 2: Nix インストール試行
# ════════════════════════════════════════════════════════════════

NIX_INSTALLED=false

if command -v nix &>/dev/null; then
  echo "==> Nix already installed: $(nix --version)"
  NIX_INSTALLED=true
else
  echo "==> Attempting to install Nix..."

  NIX_VERSION="2.28.3"
  ARCH="$(uname -m)"
  SYSTEM="${ARCH}-$(uname -s | tr '[:upper:]' '[:lower:]')"

  NIX_URL="https://releases.nixos.org/nix/nix-${NIX_VERSION}/nix-${NIX_VERSION}-${SYSTEM}.tar.xz"
  TMP_NIX="$(mktemp -d)"

  if curl -fsSL --max-time 30 "$NIX_URL" -o "${TMP_NIX}/nix.tar.xz" 2>/dev/null; then
    echo "    Downloaded Nix ${NIX_VERSION}"
    tar -xJf "${TMP_NIX}/nix.tar.xz" -C "$TMP_NIX"

    # root でのインストール準備
    if [[ "$(whoami)" == "root" ]]; then
      groupadd -f nixbld 2>/dev/null || true
      useradd -r -g nixbld -d /var/empty -s /sbin/nologin nixbld1 2>/dev/null || true
      mkdir -p "${HOME_DIR}/.config/nix"
      cat >"${HOME_DIR}/.config/nix/nix.conf" <<'NIXCONF'
build-users-group =
experimental-features = nix-command flakes pipe-operators
NIXCONF
    fi

    if "${TMP_NIX}/nix-${NIX_VERSION}-${SYSTEM}/install" --no-daemon 2>&1 | tail -5; then
      export PATH="${HOME_DIR}/.nix-profile/bin:$PATH"
      if command -v nix &>/dev/null; then
        echo "    Nix installed: $(nix --version)"
        NIX_INSTALLED=true
        # 非 root の場合も experimental-features を有効化
        if [[ "$(whoami)" != "root" ]]; then
          mkdir -p "${HOME_DIR}/.config/nix"
          grep -q "experimental-features" "${HOME_DIR}/.config/nix/nix.conf" 2>/dev/null ||
            echo "experimental-features = nix-command flakes pipe-operators" >>"${HOME_DIR}/.config/nix/nix.conf"
        fi
      fi
    else
      echo "    WARN: Nix installation failed"
    fi
  else
    echo "    WARN: Failed to download Nix (network may be restricted)"
  fi
  rm -rf "$TMP_NIX"
fi

# ════════════════════════════════════════════════════════════════
# Phase 3: Nix Home Manager でデプロイ（成功すれば exit）
# ════════════════════════════════════════════════════════════════

if [[ "$NIX_INSTALLED" == "true" ]]; then
  echo ""
  echo "==> Deploying via Nix Home Manager..."

  ARCH="$(uname -m)"
  case "$(uname -s)" in
    Darwin) export NIX_SYSTEM="${ARCH}-darwin" ;;
    Linux) export NIX_SYSTEM="${ARCH}-linux" ;;
  esac
  export USER="${USER:-$(whoami)}"

  cd "$DOTFILES_DIR"
  if nix run --impure github:nix-community/home-manager/release-25.11 -- switch -b backup --impure --flake .#default 2>&1; then
    echo ""
    echo "==> Home Manager switch completed successfully!"
    echo "    All agent configs deployed via Nix."
    exit 0
  else
    echo "    WARN: Home Manager switch failed, falling back to symlink deploy"
  fi
fi

# ════════════════════════════════════════════════════════════════
# Phase 4: フォールバック — シンボリックリンクでデプロイ
# ════════════════════════════════════════════════════════════════

echo ""
echo "==> Fallback: deploying via symlinks..."

# shellcheck source=lib/deploy-agents.sh
source "$(dirname "$0")/lib/deploy-agents.sh"

deploy_agent_configs
deploy_settings_json
deploy_codex_rules

echo ""
echo "==> Done! (fallback symlink deploy)"
echo "    - Agent definitions:  ~/.claude/agents/"
echo "    - Commands:           ~/.claude/commands/"
echo "    - Rules:              ~/.claude/rules/"
echo "    - Scripts:            ~/.claude/scripts/"
echo "    - Skills (Claude):    ~/.claude/skills/"
echo "    - Skills (Codex):     ~/.codex/skills/"
echo "    - Settings:           ~/.claude/settings.json"
echo "    - Codex rules:        ~/.codex/rules/nix-managed.rules"
