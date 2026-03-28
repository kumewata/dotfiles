#!/usr/bin/env bash
# setup-nix-web.sh - Lightweight bootstrap for Claude Code Web sessions
#
# Installs gh CLI (via tarball), deploys agent configs (via symlinks),
# and patches nix.conf to avoid Determinate Systems 403 errors.
#
# This script does NOT use Nix for package installation.
# Invoked as a SessionStart hook from .claude/settings.json.
set -euo pipefail

# ── Constants ──────────────────────────────────────────────────
DOTFILES_REPO="https://github.com/kumewata/dotfiles.git"
DOTFILES_DIR="$HOME/.dotfiles"
MARKER_FILE="$HOME/.local/state/nix-web-setup-done"
LOG_FILE="$HOME/.local/state/nix-web-setup.log"
GH_VERSION="2.67.0"

# ── Logging ────────────────────────────────────────────────────
log() { echo "[$(date '+%H:%M:%S')] $*" >&2; }

# ── Guards ─────────────────────────────────────────────────────

# Only run in Claude Code Web (Linux containers; macOS users use `hms` directly)
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] || [ "$(uname -s)" != "Linux" ]; then
  exit 0
fi

# ── Prevent parallel execution (global + project hooks may fire concurrently) ──
LOCK_FILE="$HOME/.local/state/nix-web-setup.lock"
mkdir -p "$(dirname "$LOCK_FILE")"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "[setup-nix-web] Another instance is running — skipping" >&2
  exit 0
fi

# ── Ensure USER is set ────────────────────────────────────────
export USER="${USER:-$(whoami)}"

# ── Helper: export PATH to CLAUDE_ENV_FILE (with dedup guard) ──
export_env() {
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    # Validate CLAUDE_ENV_FILE points to a safe location
    case "$CLAUDE_ENV_FILE" in
      "$HOME"/.claude/*|/tmp/*) ;;
      *) log "WARN: CLAUDE_ENV_FILE points to unexpected path: $CLAUDE_ENV_FILE — skipping"; return 0 ;;
    esac
    local path_line="export PATH=\"\$HOME/bin:/usr/local/bin:\$PATH\""
    # shellcheck disable=SC2016
    if ! grep -qF 'export PATH="$HOME/bin:/usr/local/bin' "$CLAUDE_ENV_FILE" 2>/dev/null; then
      echo "$path_line" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true
    fi
  fi
}

# ── Idempotency check (marker + artifact verification) ────────

mkdir -p "$(dirname "$MARKER_FILE")" "$(dirname "$LOG_FILE")"

artifacts_present() {
  PATH="$HOME/bin:/usr/local/bin:$PATH" command -v gh >/dev/null 2>&1 \
    && [ -f "$HOME/.claude/settings.json" ] \
    && [ -f "$HOME/.codex/rules/nix-managed.rules" ]
}

if [ -d "$DOTFILES_DIR" ]; then
  git -C "$DOTFILES_DIR" fetch --quiet origin 2>/dev/null || true
  remote_ref="$(git -C "$DOTFILES_DIR" rev-parse origin/main 2>/dev/null || echo "")"
  if [ -f "$MARKER_FILE" ] && [ -n "$remote_ref" ] \
     && [ "$(cat "$MARKER_FILE")" = "$remote_ref" ] \
     && artifacts_present; then
    log "Already set up for commit $remote_ref — skipping"
    export_env
    exit 0
  fi
fi

# ── Main setup ─────────────────────────────────────────────────

exec > >(tee -a "$LOG_FILE") 2>&1

log "Starting lightweight setup for Claude Code Web"
START_TIME=$(date +%s)

# ── Phase 1: Fix nix.conf (best-effort) ───────────────────────
# Determinate Nix's install.determinate.systems is blocked (403) in
# Claude Code Web. Patch nix.custom.conf and comment out extra-substituters
# in nix.conf itself (!include ordering means custom.conf alone is insufficient).
fix_nix_conf() {
  [ -d /etc/nix ] || return 0
  [ -w /etc/nix/nix.conf ] || return 0

  if grep -q '!include.*/nix\.custom\.conf' /etc/nix/nix.conf 2>/dev/null; then
    log "Patching nix.conf: overriding Determinate Systems endpoints..."
    if ! { cat > /etc/nix/nix.custom.conf << 'NIXCONF'
flake-registry = https://channels.nixos.org/flake-registry.json
substituters = https://cache.nixos.org/
upgrade-nix-store-path-url =
NIXCONF
    }; then
      log "WARN: Failed to write /etc/nix/nix.custom.conf; skipping nix.conf patch"
      return 0
    fi
    # Comment out Determinate Systems extra-substituters only (preserve unrelated ones)
    if ! sed -i '/install\.determinate\.systems/ s/^extra-substituters/#&/' /etc/nix/nix.conf; then
      log "WARN: Failed to patch /etc/nix/nix.conf; continuing without modification"
      return 0
    fi
    log "nix.conf patched"
  fi
}
fix_nix_conf || true

# ── Phase 2: Install gh CLI (tarball, no Nix) ─────────────────
if ! command -v gh >/dev/null 2>&1; then
  log "Installing GitHub CLI ${GH_VERSION}..."
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)  GH_ARCH="linux_amd64" ;;
    aarch64) GH_ARCH="linux_arm64" ;;
    *)       log "WARN: Unsupported architecture ${ARCH}, skipping gh install"; GH_ARCH="" ;;
  esac
  if [ -n "${GH_ARCH:-}" ]; then
    GH_URL="https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_${GH_ARCH}.tar.gz"
    GH_CHECKSUMS_URL="https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_checksums.txt"
    GH_TARBALL_NAME="gh_${GH_VERSION}_${GH_ARCH}.tar.gz"
    TMP_GH="$(mktemp -d)"
    trap 'rm -rf "$TMP_GH"' EXIT
    if curl -fsSL --connect-timeout 15 --max-time 60 "$GH_URL" -o "${TMP_GH}/gh.tar.gz" 2>/dev/null; then
      # Verify checksum if possible
      gh_verified=false
      if curl -fsSL --connect-timeout 15 --max-time 30 "$GH_CHECKSUMS_URL" -o "${TMP_GH}/checksums.txt" 2>/dev/null; then
        expected_sha256="$(grep " ${GH_TARBALL_NAME}$" "${TMP_GH}/checksums.txt" | awk '{print $1}')"
        if [ -n "${expected_sha256:-}" ] && command -v sha256sum >/dev/null 2>&1; then
          actual_sha256="$(sha256sum "${TMP_GH}/gh.tar.gz" | awk '{print $1}')"
          if [ "$expected_sha256" = "$actual_sha256" ]; then
            gh_verified=true
          else
            log "ERROR: SHA256 checksum mismatch for gh tarball; skipping install"
          fi
        else
          log "WARN: Cannot verify checksum (missing sha256sum or checksum entry); installing without verification"
          gh_verified=true
        fi
      else
        log "WARN: Failed to download checksums; installing without verification"
        gh_verified=true
      fi
      if [ "$gh_verified" = true ]; then
        tar -xzf "${TMP_GH}/gh.tar.gz" -C "$TMP_GH"
        if [ -w /usr/local/bin ]; then
          cp "${TMP_GH}/gh_${GH_VERSION}_${GH_ARCH}/bin/gh" /usr/local/bin/gh
          log "Installed gh ${GH_VERSION} to /usr/local/bin/gh"
        else
          mkdir -p "$HOME/bin"
          cp "${TMP_GH}/gh_${GH_VERSION}_${GH_ARCH}/bin/gh" "$HOME/bin/gh"
          log "Installed gh ${GH_VERSION} to $HOME/bin/gh"
        fi
      fi
    else
      log "WARN: Failed to download gh CLI"
    fi
    rm -rf "$TMP_GH"
    trap - EXIT
  fi
else
  log "gh already installed: $(gh --version | head -1)"
fi

# ── Phase 3: Clone/update dotfiles + deploy agent configs ─────
if [ -d "$DOTFILES_DIR" ]; then
  log "Updating dotfiles..."
  git -C "$DOTFILES_DIR" merge --ff-only origin/main \
    || git -C "$DOTFILES_DIR" pull --ff-only \
    || log "WARN: git pull failed — proceeding with current checkout"
else
  log "Cloning dotfiles..."
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR" \
    || { log "ERROR: Failed to clone dotfiles"; exit 1; }
fi

HOME_DIR="$HOME"
AGENTS_DIR="${DOTFILES_DIR}/config/agents"

if [ -f "${DOTFILES_DIR}/lib/deploy-agents.sh" ]; then
  # shellcheck source=lib/deploy-agents.sh
  source "${DOTFILES_DIR}/lib/deploy-agents.sh"

  deploy_agent_configs
  deploy_settings_json
  deploy_codex_rules
else
  log "WARN: lib/deploy-agents.sh not found in dotfiles (stale checkout?) — skipping agent deploy"
fi

log "Agent configs deployed"

# ── Phase 4: Export PATH + write marker ────────────────────────
export_env

current_ref="$(git -C "$DOTFILES_DIR" rev-parse HEAD)"
echo "$current_ref" > "$MARKER_FILE"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log "Setup complete in ${DURATION}s (commit: $current_ref)"

# Drain tee subprocess to avoid truncated log output
wait
