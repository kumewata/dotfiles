#!/usr/bin/env bash
# setup-without-nix.sh — Nix/Home Manager なしで Claude Code / Codex の設定をデプロイ
# agent-skills.nix 相当のシンボリックリンク・ファイル配置を行う
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

# ── CLI ツールのインストール ──

# GitHub CLI (gh)
if ! command -v gh &>/dev/null; then
  echo "==> Installing GitHub CLI (gh)..."
  GH_VERSION="2.67.0"
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)  GH_ARCH="linux_amd64" ;;
    aarch64) GH_ARCH="linux_arm64" ;;
    arm64)   GH_ARCH="macOS_arm64" ;;  # macOS Apple Silicon
    *)       echo "    WARN: Unsupported architecture ${ARCH}, skipping gh install"; GH_ARCH="" ;;
  esac
  if [[ -n "${GH_ARCH:-}" ]]; then
    GH_URL="https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_${GH_ARCH}.tar.gz"
    TMP_GH="$(mktemp -d)"
    if curl -fsSL "$GH_URL" -o "${TMP_GH}/gh.tar.gz" 2>/dev/null; then
      tar -xzf "${TMP_GH}/gh.tar.gz" -C "$TMP_GH"
      # Install to /usr/local/bin if writable, else ~/bin
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

# ── ディレクトリ作成 ──
mkdir -p "${HOME_DIR}/.claude/agents"
mkdir -p "${HOME_DIR}/.claude/commands"
mkdir -p "${HOME_DIR}/.claude/rules"
mkdir -p "${HOME_DIR}/.claude/scripts"
mkdir -p "${HOME_DIR}/.claude/skills"
mkdir -p "${HOME_DIR}/.codex/skills"
mkdir -p "${HOME_DIR}/.codex/rules"

# ── ヘルパー: シンボリックリンク作成（既存は上書き） ──
link_file() {
  local src="$1" dst="$2"
  if [[ -e "$dst" || -L "$dst" ]]; then
    rm -f "$dst"
  fi
  ln -s "$src" "$dst"
  echo "    ${dst} -> ${src}"
}

# ── エージェント定義 → ~/.claude/agents/ ──
echo "==> Agent definitions"
for f in "${AGENTS_DIR}/definitions/"*.md; do
  [[ -f "$f" ]] || continue
  name="$(basename "$f")"
  link_file "$f" "${HOME_DIR}/.claude/agents/${name}"
done

# ── コマンド → ~/.claude/commands/ ──
echo "==> Commands"
for f in "${AGENTS_DIR}/commands/"*.md; do
  [[ -f "$f" ]] || continue
  name="$(basename "$f")"
  link_file "$f" "${HOME_DIR}/.claude/commands/${name}"
done

# ── ルール → ~/.claude/rules/ ──
echo "==> Rules"
for f in "${AGENTS_DIR}/rules/"*.md; do
  [[ -f "$f" ]] || continue
  name="$(basename "$f")"
  link_file "$f" "${HOME_DIR}/.claude/rules/${name}"
done

# ── スクリプト → ~/.claude/scripts/ ──
echo "==> Scripts"
for f in "${AGENTS_DIR}/scripts/"*; do
  [[ -f "$f" ]] || continue
  name="$(basename "$f")"
  link_file "$f" "${HOME_DIR}/.claude/scripts/${name}"
  chmod +x "${HOME_DIR}/.claude/scripts/${name}"
done

# ── スキル → ~/.claude/skills/ & ~/.codex/skills/ ──
echo "==> Skills (Claude Code)"
for d in "${AGENTS_DIR}/skills/"*/; do
  [[ -d "$d" ]] || continue
  name="$(basename "$d")"
  # .system ディレクトリは除外
  [[ "$name" == ".system" ]] && continue
  link_file "$d" "${HOME_DIR}/.claude/skills/${name}"
done

echo "==> Skills (Codex)"
for d in "${AGENTS_DIR}/skills/"*/; do
  [[ -d "$d" ]] || continue
  name="$(basename "$d")"
  [[ "$name" == ".system" ]] && continue
  link_file "$d" "${HOME_DIR}/.codex/skills/${name}"
done

# ── settings.json のマージ ──
echo "==> Claude Code settings.json"
SETTINGS_FILE="${HOME_DIR}/.claude/settings.json"

# agent-skills.nix で定義されている設定を生成
NEW_SETTINGS=$(cat <<'SETTINGS_EOF'
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/scripts/statusline.sh"
  },
  "enableAllProjectMcpServers": false,
  "permissions": {
    "disableBypassPermissionsMode": "disable",
    "additionalDirectories": [
      "~/.local/state/steering"
    ],
    "allow": [
      "Read",
      "Edit",
      "Write",
      "WebSearch",
      "WebFetch",
      "Agent",
      "Skill",
      "MCP",
      "Bash(git status*)",
      "Bash(git diff*)",
      "Bash(git log*)",
      "Bash(git show*)",
      "Bash(git blame*)",
      "Bash(git branch*)",
      "Bash(git fetch*)",
      "Bash(git pull*)",
      "Bash(git add*)",
      "Bash(git commit*)",
      "Bash(git switch*)",
      "Bash(git stash*)",
      "Bash(git tag*)",
      "Bash(git remote*)",
      "Bash(git rev-parse*)",
      "Bash(git ls-files*)",
      "Bash(git shortlog*)",
      "Bash(git config --get*)",
      "Bash(git config --list*)",
      "Bash(gh pr view*)",
      "Bash(gh run list*)",
      "Bash(gh run view*)",
      "Bash(gh issue view*)",
      "Bash(npm run *)",
      "Bash(npm test*)",
      "Bash(npm ci*)",
      "Bash(npm ls*)",
      "Bash(npm outdated*)",
      "Bash(npm info*)",
      "Bash(pnpm run *)",
      "Bash(pnpm test*)",
      "Bash(pnpm ls*)",
      "Bash(yarn run *)",
      "Bash(yarn test*)",
      "Bash(bun run *)",
      "Bash(bun test*)",
      "Bash(make test*)",
      "Bash(make build*)",
      "Bash(make check*)",
      "Bash(cargo build*)",
      "Bash(cargo test*)",
      "Bash(cargo check*)",
      "Bash(cargo clippy*)",
      "Bash(cargo fmt*)",
      "Bash(terraform init*)",
      "Bash(terraform plan*)",
      "Bash(terraform validate*)",
      "Bash(terraform fmt*)",
      "Bash(terraform show*)",
      "Bash(terraform output*)",
      "Bash(terraform state list*)",
      "Bash(terraform state show*)",
      "Bash(node --version*)",
      "Bash(python --version*)",
      "Bash(python -m pytest*)",
      "Bash(python -m pip list*)",
      "Bash(mise *)",
      "Bash(ls*)",
      "Bash(pwd)",
      "Bash(echo *)",
      "Bash(wc *)",
      "Bash(sort *)",
      "Bash(uniq *)",
      "Bash(cut *)",
      "Bash(tr *)",
      "Bash(mkdir *)",
      "Bash(touch *)",
      "Bash(find *)",
      "Bash(grep *)",
      "Bash(rg *)",
      "Bash(fd *)",
      "Bash(jq *)",
      "Bash(yq *)",
      "Bash(diff *)",
      "Bash(file *)",
      "Bash(stat *)",
      "Bash(which *)",
      "Bash(date*)",
      "Bash(printf *)",
      "Bash(basename *)",
      "Bash(dirname *)",
      "Bash(realpath *)",
      "Bash(true*)",
      "Bash(false*)",
      "Bash(test *)",
      "Bash([ *)"
    ],
    "ask": [
      "Bash(nix *)",
      "Bash(nix-store *)",
      "Bash(gh *)",
      "Bash(npm install*)",
      "Bash(pnpm install*)",
      "Bash(yarn install*)",
      "Bash(bun install*)",
      "Bash(codex *)",
      "Bash(git push*)",
      "Bash(npm publish*)",
      "Bash(gh pr merge*)",
      "Bash(git rebase*)",
      "Bash(git merge*)",
      "Bash(git checkout*)",
      "Bash(git restore*)",
      "Bash(rm *)",
      "Bash(mv *)",
      "Bash(cp *)",
      "Bash(chmod *)",
      "Bash(terraform apply*)",
      "Bash(terraform destroy*)",
      "Bash(terraform import*)",
      "Bash(sed *)",
      "Bash(awk *)",
      "Bash(xargs *)",
      "Bash(tee *)",
      "Bash(make *)",
      "Bash(make)",
      "Bash(node *)",
      "Bash(python *)",
      "Bash(cargo run*)"
    ],
    "deny": [
      "Bash(sudo *)",
      "Bash(rm -rf /)",
      "Bash(rm -rf /*)",
      "Bash(rm -rf ~*)",
      "Bash(rm -fr *)",
      "Bash(mkfs *)",
      "Bash(dd *)",
      "Bash(diskutil erase*)",
      "Bash(shutdown *)",
      "Bash(reboot*)",
      "Bash(bash*)",
      "Bash(sh *)",
      "Bash(sh)",
      "Bash(zsh*)",
      "Bash(dash*)",
      "Bash(eval *)",
      "Bash(exec *)",
      "Bash(source *)",
      "Bash(curl *)",
      "Bash(wget *)",
      "Bash(nc *)",
      "Bash(ncat *)",
      "Bash(telnet *)",
      "Bash(scp *)",
      "Bash(scp)",
      "Bash(rsync *)",
      "Bash(rsync)",
      "Bash(sftp *)",
      "Bash(sftp)",
      "Bash(ftp *)",
      "Bash(ftp)",
      "Bash(ssh *)",
      "Bash(ssh)",
      "Bash(* .env*)",
      "Bash(* ~/.ssh/*)",
      "Bash(* ~/.aws/*)",
      "Bash(* ~/.config/gh/*)",
      "Bash(* ~/.git-credentials)",
      "Bash(* ~/.netrc)",
      "Bash(* ~/.npmrc)",
      "Bash(chmod 777 *)",
      "Bash(chmod -R 777 *)",
      "Bash(chmod 0777 *)",
      "Bash(chmod a+rwx *)",
      "Bash(chown *)",
      "Bash(chgrp *)",
      "Bash(git push --force*)",
      "Bash(git push * --force*)",
      "Bash(git push -f *)",
      "Bash(git push * -f *)",
      "Bash(git reset --hard*)",
      "Bash(git clean *)",
      "Bash(git checkout -f *)",
      "Bash(git checkout -- .)",
      "Bash(git switch -f *)",
      "Bash(git branch -D *)",
      "Bash(git tag -d *)",
      "Bash(git reflog expire*)",
      "Bash(git restore .)",
      "Bash(git restore --worktree .)"
    ]
  }
}
SETTINGS_EOF
)

# 既存の settings.json があればマージ、なければ新規作成
if [[ -f "$SETTINGS_FILE" ]] && command -v jq &>/dev/null; then
  echo "    Merging with existing settings.json"
  EXISTING=$(cat "$SETTINGS_FILE")
  # 既存の hooks 等を保持しつつ、新しい設定をマージ
  echo "$EXISTING" | jq --argjson new "$NEW_SETTINGS" '
    # 既存の permissions.allow に新規を追加（重複排除）
    ($new.permissions.allow // []) as $new_allow |
    (.permissions.allow // []) as $old_allow |
    ($old_allow + $new_allow | unique) as $merged_allow |
    # マージ
    . * $new |
    .permissions.allow = $merged_allow
  ' > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
else
  echo "    Writing new settings.json"
  echo "$NEW_SETTINGS" > "$SETTINGS_FILE"
fi

# ── Codex CLI ルール ──
echo "==> Codex CLI rules"
cat > "${HOME_DIR}/.codex/rules/nix-managed.rules" <<'CODEX_EOF'
# ── allow: 自動許可 ──

# Git（安全なサブコマンド）
prefix_rule(pattern=["git", "status"], decision="allow")
prefix_rule(pattern=["git", "diff"], decision="allow")
prefix_rule(pattern=["git", "log"], decision="allow")
prefix_rule(pattern=["git", "show"], decision="allow")
prefix_rule(pattern=["git", "blame"], decision="allow")
prefix_rule(pattern=["git", "branch"], decision="allow")
prefix_rule(pattern=["git", "fetch"], decision="allow")
prefix_rule(pattern=["git", "pull"], decision="allow")
prefix_rule(pattern=["git", "add"], decision="allow")
prefix_rule(pattern=["git", "commit"], decision="allow")
prefix_rule(pattern=["git", "switch"], decision="allow")
prefix_rule(pattern=["git", "stash"], decision="allow")
prefix_rule(pattern=["git", "tag"], decision="allow")
prefix_rule(pattern=["git", "remote"], decision="allow")
prefix_rule(pattern=["git", "rev-parse"], decision="allow")
prefix_rule(pattern=["git", "ls-files"], decision="allow")
prefix_rule(pattern=["git", "shortlog"], decision="allow")
prefix_rule(pattern=["git", "config", "--get"], decision="allow")
prefix_rule(pattern=["git", "config", "--list"], decision="allow")

# GitHub CLI（read-only 系のみ）
prefix_rule(pattern=["gh", "pr", "view"], decision="allow")
prefix_rule(pattern=["gh", "run", "list"], decision="allow")
prefix_rule(pattern=["gh", "run", "view"], decision="allow")
prefix_rule(pattern=["gh", "issue", "view"], decision="allow")

# Package managers（read / build / test）
prefix_rule(pattern=["npm", "run"], decision="allow")
prefix_rule(pattern=["npm", "test"], decision="allow")
prefix_rule(pattern=["npm", "ci"], decision="allow")
prefix_rule(pattern=["npm", "ls"], decision="allow")
prefix_rule(pattern=["npm", "outdated"], decision="allow")
prefix_rule(pattern=["npm", "info"], decision="allow")
prefix_rule(pattern=["pnpm", "run"], decision="allow")
prefix_rule(pattern=["pnpm", "test"], decision="allow")
prefix_rule(pattern=["pnpm", "ls"], decision="allow")
prefix_rule(pattern=["yarn", "run"], decision="allow")
prefix_rule(pattern=["yarn", "test"], decision="allow")
prefix_rule(pattern=["bun", "run"], decision="allow")
prefix_rule(pattern=["bun", "test"], decision="allow")

# Build tools
prefix_rule(pattern=["make", "test"], decision="allow")
prefix_rule(pattern=["make", "build"], decision="allow")
prefix_rule(pattern=["make", "check"], decision="allow")
prefix_rule(pattern=["cargo", "build"], decision="allow")
prefix_rule(pattern=["cargo", "test"], decision="allow")
prefix_rule(pattern=["cargo", "check"], decision="allow")
prefix_rule(pattern=["cargo", "clippy"], decision="allow")
prefix_rule(pattern=["cargo", "fmt"], decision="allow")
prefix_rule(pattern=["terraform", "init"], decision="allow")
prefix_rule(pattern=["terraform", "plan"], decision="allow")
prefix_rule(pattern=["terraform", "validate"], decision="allow")
prefix_rule(pattern=["terraform", "fmt"], decision="allow")
prefix_rule(pattern=["terraform", "show"], decision="allow")
prefix_rule(pattern=["terraform", "output"], decision="allow")
prefix_rule(pattern=["terraform", "state", "list"], decision="allow")
prefix_rule(pattern=["terraform", "state", "show"], decision="allow")

# Runtime
prefix_rule(pattern=["node", "--version"], decision="allow")
prefix_rule(pattern=["python", "--version"], decision="allow")
prefix_rule(pattern=["python", "-m", "pytest"], decision="allow")
prefix_rule(pattern=["python", "-m", "pip", "list"], decision="allow")
prefix_rule(pattern=["mise"], decision="allow")

# Shell utilities
prefix_rule(pattern=["ls"], decision="allow")
prefix_rule(pattern=["pwd"], decision="allow")
prefix_rule(pattern=["echo"], decision="allow")
prefix_rule(pattern=["wc"], decision="allow")
prefix_rule(pattern=["sort"], decision="allow")
prefix_rule(pattern=["uniq"], decision="allow")
prefix_rule(pattern=["cut"], decision="allow")
prefix_rule(pattern=["tr"], decision="allow")
prefix_rule(pattern=["mkdir"], decision="allow")
prefix_rule(pattern=["touch"], decision="allow")
prefix_rule(pattern=["find"], decision="allow")
prefix_rule(pattern=["grep"], decision="allow")
prefix_rule(pattern=["rg"], decision="allow")
prefix_rule(pattern=["fd"], decision="allow")
prefix_rule(pattern=["jq"], decision="allow")
prefix_rule(pattern=["yq"], decision="allow")
prefix_rule(pattern=["diff"], decision="allow")
prefix_rule(pattern=["file"], decision="allow")
prefix_rule(pattern=["stat"], decision="allow")
prefix_rule(pattern=["which"], decision="allow")
prefix_rule(pattern=["date"], decision="allow")
prefix_rule(pattern=["printf"], decision="allow")
prefix_rule(pattern=["basename"], decision="allow")
prefix_rule(pattern=["dirname"], decision="allow")
prefix_rule(pattern=["realpath"], decision="allow")
prefix_rule(pattern=["true"], decision="allow")
prefix_rule(pattern=["false"], decision="allow")
prefix_rule(pattern=["test"], decision="allow")
prefix_rule(pattern=["["], decision="allow")

# ── prompt: 確認が必要 ──
prefix_rule(pattern=["nix"], decision="prompt")
prefix_rule(pattern=["nix-store"], decision="prompt")
prefix_rule(pattern=["gh"], decision="prompt")
prefix_rule(pattern=["npm", "install"], decision="prompt")
prefix_rule(pattern=["pnpm", "install"], decision="prompt")
prefix_rule(pattern=["yarn", "install"], decision="prompt")
prefix_rule(pattern=["bun", "install"], decision="prompt")
prefix_rule(pattern=["codex"], decision="prompt")
prefix_rule(pattern=["git", "push"], decision="prompt")
prefix_rule(pattern=["npm", "publish"], decision="prompt")
prefix_rule(pattern=["gh", "pr", "merge"], decision="prompt")
prefix_rule(pattern=["git", "rebase"], decision="prompt")
prefix_rule(pattern=["git", "merge"], decision="prompt")
prefix_rule(pattern=["git", "checkout"], decision="prompt")
prefix_rule(pattern=["git", "restore"], decision="prompt")
prefix_rule(pattern=["rm"], decision="prompt")
prefix_rule(pattern=["mv"], decision="prompt")
prefix_rule(pattern=["cp"], decision="prompt")
prefix_rule(pattern=["chmod"], decision="prompt")
prefix_rule(pattern=["terraform", "apply"], decision="prompt")
prefix_rule(pattern=["terraform", "destroy"], decision="prompt")
prefix_rule(pattern=["terraform", "import"], decision="prompt")
prefix_rule(pattern=["sed"], decision="prompt")
prefix_rule(pattern=["awk"], decision="prompt")
prefix_rule(pattern=["xargs"], decision="prompt")
prefix_rule(pattern=["tee"], decision="prompt")
prefix_rule(pattern=["make"], decision="prompt")
prefix_rule(pattern=["node"], decision="prompt")
prefix_rule(pattern=["python"], decision="prompt")
prefix_rule(pattern=["cargo", "run"], decision="prompt")

# ── forbidden: 完全ブロック ──
prefix_rule(pattern=["sudo"], decision="forbidden")
prefix_rule(pattern=["rm", "-rf", "/"], decision="forbidden")
prefix_rule(pattern=["rm", "-rf", "~"], decision="forbidden")
prefix_rule(pattern=["rm", "-fr"], decision="forbidden")
prefix_rule(pattern=["mkfs"], decision="forbidden")
prefix_rule(pattern=["dd"], decision="forbidden")
prefix_rule(pattern=["diskutil", "erase"], decision="forbidden")
prefix_rule(pattern=["shutdown"], decision="forbidden")
prefix_rule(pattern=["reboot"], decision="forbidden")
prefix_rule(pattern=["bash"], decision="forbidden")
prefix_rule(pattern=["sh"], decision="forbidden")
prefix_rule(pattern=["zsh"], decision="forbidden")
prefix_rule(pattern=["dash"], decision="forbidden")
prefix_rule(pattern=["eval"], decision="forbidden")
prefix_rule(pattern=["exec"], decision="forbidden")
prefix_rule(pattern=["source"], decision="forbidden")
prefix_rule(pattern=["curl"], decision="forbidden")
prefix_rule(pattern=["wget"], decision="forbidden")
prefix_rule(pattern=["nc"], decision="forbidden")
prefix_rule(pattern=["ncat"], decision="forbidden")
prefix_rule(pattern=["telnet"], decision="forbidden")
prefix_rule(pattern=["scp"], decision="forbidden")
prefix_rule(pattern=["rsync"], decision="forbidden")
prefix_rule(pattern=["sftp"], decision="forbidden")
prefix_rule(pattern=["ftp"], decision="forbidden")
prefix_rule(pattern=["ssh"], decision="forbidden")
prefix_rule(pattern=["chmod", "777"], decision="forbidden")
prefix_rule(pattern=["chmod", "-R", "777"], decision="forbidden")
prefix_rule(pattern=["chmod", "0777"], decision="forbidden")
prefix_rule(pattern=["chmod", "a+rwx"], decision="forbidden")
prefix_rule(pattern=["chown"], decision="forbidden")
prefix_rule(pattern=["chgrp"], decision="forbidden")
prefix_rule(pattern=["git", "push", "--force"], decision="forbidden")
prefix_rule(pattern=["git", "push", "-f"], decision="forbidden")
prefix_rule(pattern=["git", "reset", "--hard"], decision="forbidden")
prefix_rule(pattern=["git", "clean"], decision="forbidden")
prefix_rule(pattern=["git", "checkout", "-f"], decision="forbidden")
prefix_rule(pattern=["git", "checkout", "--", "."], decision="forbidden")
prefix_rule(pattern=["git", "switch", "-f"], decision="forbidden")
prefix_rule(pattern=["git", "branch", "-D"], decision="forbidden")
prefix_rule(pattern=["git", "tag", "-d"], decision="forbidden")
prefix_rule(pattern=["git", "reflog", "expire"], decision="forbidden")
prefix_rule(pattern=["git", "restore", "."], decision="forbidden")
prefix_rule(pattern=["git", "restore", "--worktree", "."], decision="forbidden")
CODEX_EOF

echo ""
echo "==> Done! Deployed:"
echo "    - Agent definitions:  ~/.claude/agents/"
echo "    - Commands:           ~/.claude/commands/"
echo "    - Rules:              ~/.claude/rules/"
echo "    - Scripts:            ~/.claude/scripts/"
echo "    - Skills (Claude):    ~/.claude/skills/"
echo "    - Skills (Codex):     ~/.codex/skills/"
echo "    - Settings:           ~/.claude/settings.json"
echo "    - Codex rules:        ~/.codex/rules/nix-managed.rules"
