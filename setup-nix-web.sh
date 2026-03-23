#!/usr/bin/env bash
# setup-nix-web.sh - Bootstrap Nix + Home Manager in Claude Code Web sessions
#
# This script is idempotent: safe to run multiple times.
# It installs Nix (single-user mode), clones the dotfiles repo,
# and runs Home Manager to deploy packages and agent configurations.
#
# Invoked as a SessionStart hook from .claude/settings.json.
# CWD is the project root when invoked by Claude Code.
set -euo pipefail

# ── Constants ──────────────────────────────────────────────────
DOTFILES_REPO="https://github.com/kumewata/dotfiles.git"
DOTFILES_DIR="$HOME/.dotfiles"
MARKER_FILE="$HOME/.local/state/nix-web-setup-done"
LOG_FILE="$HOME/.local/state/nix-web-setup.log"

# ── Detect architecture ───────────────────────────────────────
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  NIX_SYSTEM_VALUE="x86_64-linux" ;;
  aarch64) NIX_SYSTEM_VALUE="aarch64-linux" ;;
  *)       echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

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

# ── Ensure USER is set (required by nix.sh profile script) ────
export USER="${USER:-$(whoami)}"

# ── Helper functions ───────────────────────────────────────────

source_nix_env() {
  for profile_script in \
    "$HOME/.nix-profile/etc/profile.d/nix.sh" \
    "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" \
    "/nix/var/nix/profiles/default/etc/profile.d/nix.sh"; do
    if [ -f "$profile_script" ]; then
      # shellcheck disable=SC1090
      . "$profile_script"
      break
    fi
  done
}

export_env() {
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    {
      echo "export PATH=\"$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:\$PATH\""
      echo "export NIX_SYSTEM=$NIX_SYSTEM_VALUE"
    } >> "$CLAUDE_ENV_FILE"
  fi
}

# ── Idempotency check ─────────────────────────────────────────

mkdir -p "$(dirname "$MARKER_FILE")" "$(dirname "$LOG_FILE")"

if [ -d "$DOTFILES_DIR" ]; then
  # Fetch latest from remote so we compare against the newest commit
  git -C "$DOTFILES_DIR" fetch --quiet origin 2>/dev/null || true
  remote_ref="$(git -C "$DOTFILES_DIR" rev-parse origin/main 2>/dev/null || echo "")"
  if [ -f "$MARKER_FILE" ] && [ -n "$remote_ref" ] && [ "$(cat "$MARKER_FILE")" = "$remote_ref" ]; then
    log "Already set up for commit $remote_ref — skipping"
    source_nix_env
    export_env
    exit 0
  fi
fi

# ── Main setup ─────────────────────────────────────────────────

# Redirect stdout+stderr to log file (via tee so stderr is also captured)
exec > >(tee -a "$LOG_FILE") 2>&1

log "Starting Nix environment setup for Claude Code Web"
START_TIME=$(date +%s)

# 1. Install Nix (single-user, no daemon)
if ! command -v nix >/dev/null 2>&1; then
  log "Installing Nix (single-user mode)..."

  nix_installed=false

  # Method A: Determinate Systems installer (preferred)
  TMP_INSTALLER="$(mktemp)"
  trap 'rm -f "$TMP_INSTALLER"' EXIT
  if curl --proto '=https' --tlsv1.2 -sSfL \
       --connect-timeout 15 --max-time 120 \
       https://install.determinate.systems/nix \
       -o "$TMP_INSTALLER" 2>/dev/null; then
    if sh "$TMP_INSTALLER" install linux \
         --init none \
         --no-confirm \
         --diagnostic-endpoint "" 2>&1; then
      nix_installed=true
      log "Nix installed via Determinate Systems installer"
    else
      log "WARN: Determinate Systems installer failed — trying fallback"
    fi
  else
    log "WARN: Could not download Determinate Systems installer — trying fallback"
  fi
  rm -f "$TMP_INSTALLER"
  trap - EXIT

  # Method B: Official nixos.org tarball (fallback)
  if [ "$nix_installed" = false ]; then
    NIX_VERSION="2.28.3"
    TARBALL_URL="https://releases.nixos.org/nix/nix-${NIX_VERSION}/nix-${NIX_VERSION}-${ARCH}-linux.tar.xz"
    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_DIR"' EXIT

    log "Downloading Nix ${NIX_VERSION} from nixos.org..."
    curl --proto '=https' --tlsv1.2 -sSfL \
      --connect-timeout 15 --max-time 180 \
      "$TARBALL_URL" -o "$TMP_DIR/nix.tar.xz" \
      || { log "ERROR: Failed to download Nix tarball"; exit 1; }

    tar xf "$TMP_DIR/nix.tar.xz" -C "$TMP_DIR"

    # Ensure nixbld group exists (required by installer)
    groupadd -f nixbld 2>/dev/null || true
    # Configure single-user mode (no build-users-group)
    mkdir -p /etc/nix
    if ! grep -q "^build-users-group" /etc/nix/nix.conf 2>/dev/null; then
      echo "build-users-group = " >> /etc/nix/nix.conf
    fi
    if ! grep -q "experimental-features" /etc/nix/nix.conf 2>/dev/null; then
      echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf
    fi

    # Run the official installer in single-user (no-daemon) mode
    bash "$TMP_DIR"/nix-*-linux/install --no-daemon \
      || { log "ERROR: Nix tarball installation failed"; exit 1; }

    rm -rf "$TMP_DIR"
    trap - EXIT
    log "Nix installed via official tarball"
  fi
else
  log "Nix already installed — skipping installation"
fi

# 2. Source Nix environment
source_nix_env

if ! command -v nix >/dev/null 2>&1; then
  log "ERROR: nix command not found after installation"
  exit 1
fi

# 3. Clone or update dotfiles
if [ -d "$DOTFILES_DIR" ]; then
  log "Updating dotfiles..."
  # fetch was already done in idempotency check; just fast-forward merge
  git -C "$DOTFILES_DIR" merge --ff-only origin/main 2>/dev/null \
    || git -C "$DOTFILES_DIR" pull --ff-only \
    || log "WARN: git pull failed — proceeding with current checkout"
else
  log "Cloning dotfiles..."
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR" \
    || { log "ERROR: Failed to clone dotfiles"; exit 1; }
fi

# 4. Run Home Manager switch
log "Running Home Manager switch ($NIX_SYSTEM_VALUE)..."
export NIX_SYSTEM="$NIX_SYSTEM_VALUE"
export USER="${USER:-$(whoami)}"

nix run --impure "github:nix-community/home-manager/release-25.11" \
  -- switch --impure --flake "$DOTFILES_DIR#default" -b backup \
  || { log "ERROR: Home Manager switch failed"; exit 1; }

log "Home Manager switch completed"

# 5. Export environment for Claude Code
export_env

# 6. Write marker file
current_ref="$(git -C "$DOTFILES_DIR" rev-parse HEAD)"
echo "$current_ref" > "$MARKER_FILE"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log "Setup complete in ${DURATION}s (commit: $current_ref)"

# Drain tee subprocess to avoid truncated log output
wait
