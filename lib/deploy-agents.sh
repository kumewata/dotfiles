#!/usr/bin/env bash
# lib/deploy-agents.sh — Shared agent config deployment functions
#
# Sourced by both setup.sh and setup-web.sh.
# Requires: HOME_DIR and AGENTS_DIR to be set before sourcing.

if [[ -z "${HOME_DIR:-}" ]]; then
  echo "deploy-agents.sh: HOME_DIR must be set and non-empty before sourcing this library." >&2
  # shellcheck disable=SC2317
  return 1 2>/dev/null || exit 1
fi

if [[ -z "${AGENTS_DIR:-}" ]]; then
  echo "deploy-agents.sh: AGENTS_DIR must be set and non-empty before sourcing this library." >&2
  # shellcheck disable=SC2317
  return 1 2>/dev/null || exit 1
fi

# ── link_file ─────────────────────────────────────────────────
# Create a symlink, replacing any existing file or link at the destination.
link_file() {
  local src="$1" dst="$2"
  if [[ -d "$dst" && ! -L "$dst" ]]; then
    rm -rf "$dst"
  elif [[ -e "$dst" || -L "$dst" ]]; then
    rm -f "$dst"
  fi
  ln -s "$src" "$dst"
  echo "    ${dst} -> ${src}"
}

# ── deploy_agent_configs ──────────────────────────────────────
# Deploy agent definitions, commands, rules, scripts, and skills
# via symlinks for both Claude Code and Codex.
deploy_agent_configs() {
  mkdir -p "${HOME_DIR}/.claude/agents"
  mkdir -p "${HOME_DIR}/.claude/commands"
  mkdir -p "${HOME_DIR}/.claude/rules"
  mkdir -p "${HOME_DIR}/.claude/scripts"
  mkdir -p "${HOME_DIR}/.claude/skills"
  mkdir -p "${HOME_DIR}/.codex/skills"
  mkdir -p "${HOME_DIR}/.codex/rules"

  echo "==> Agent definitions"
  for f in "${AGENTS_DIR}/definitions/"*.md; do
    [[ -f "$f" ]] || continue
    link_file "$f" "${HOME_DIR}/.claude/agents/$(basename "$f")"
  done

  echo "==> Commands"
  for f in "${AGENTS_DIR}/commands/"*.md; do
    [[ -f "$f" ]] || continue
    link_file "$f" "${HOME_DIR}/.claude/commands/$(basename "$f")"
  done

  echo "==> Rules"
  for f in "${AGENTS_DIR}/rules/"*.md; do
    [[ -f "$f" ]] || continue
    link_file "$f" "${HOME_DIR}/.claude/rules/$(basename "$f")"
  done

  echo "==> Scripts"
  for f in "${AGENTS_DIR}/scripts/"*; do
    [[ -f "$f" ]] || continue
    link_file "$f" "${HOME_DIR}/.claude/scripts/$(basename "$f")"
    chmod +x "${HOME_DIR}/.claude/scripts/$(basename "$f")"
  done

  echo "==> Skills (Claude Code)"
  for d in "${AGENTS_DIR}/skills/"*/; do
    [[ -d "$d" ]] || continue
    local name
    name="$(basename "$d")"
    [[ "$name" == ".system" ]] && continue
    link_file "$d" "${HOME_DIR}/.claude/skills/${name}"
  done

  echo "==> Skills (Codex)"
  for d in "${AGENTS_DIR}/skills/"*/; do
    [[ -d "$d" ]] || continue
    local name
    name="$(basename "$d")"
    [[ "$name" == ".system" ]] && continue
    link_file "$d" "${HOME_DIR}/.codex/skills/${name}"
  done
}

# ── deploy_settings_json ──────────────────────────────────────
# Write or merge ~/.claude/settings.json.
# Merge semantics: permissions.allow is unioned (existing + new, deduplicated).
# All other fields (including permissions.ask and permissions.deny) are overwritten
# by the new settings blob.
deploy_settings_json() {
  echo "==> Claude Code settings.json"
  local settings_file="${HOME_DIR}/.claude/settings.json"

  local new_settings
  new_settings=$(
    cat <<'SETTINGS_EOF'
{
  "statusLine": {"type": "command", "command": "~/.claude/scripts/statusline.sh"},
  "enableAllProjectMcpServers": false,
  "permissions": {
    "disableBypassPermissionsMode": "disable",
    "additionalDirectories": ["~/.local/state/steering"],
    "allow": [
      "Read","Edit","Write","WebSearch","WebFetch","Agent","Skill","MCP",
      "Bash(git status*)","Bash(git diff*)","Bash(git log*)","Bash(git show*)",
      "Bash(git blame*)","Bash(git branch*)","Bash(git fetch*)","Bash(git pull*)",
      "Bash(git add*)","Bash(git commit*)","Bash(git switch*)","Bash(git stash*)",
      "Bash(git tag*)","Bash(git remote*)","Bash(git rev-parse*)","Bash(git ls-files*)",
      "Bash(git shortlog*)","Bash(git config --get*)","Bash(git config --list*)",
      "Bash(gh pr view*)","Bash(gh run list*)","Bash(gh run view*)","Bash(gh issue view*)",
      "Bash(npm run *)","Bash(npm test*)","Bash(npm ci*)","Bash(npm ls*)",
      "Bash(npm outdated*)","Bash(npm info*)","Bash(pnpm run *)","Bash(pnpm test*)",
      "Bash(pnpm ls*)","Bash(yarn run *)","Bash(yarn test*)","Bash(bun run *)",
      "Bash(bun test*)","Bash(make test*)","Bash(make build*)","Bash(make check*)",
      "Bash(cargo build*)","Bash(cargo test*)","Bash(cargo check*)","Bash(cargo clippy*)",
      "Bash(cargo fmt*)","Bash(terraform init*)","Bash(terraform plan*)",
      "Bash(terraform validate*)","Bash(terraform fmt*)","Bash(terraform show*)",
      "Bash(terraform output*)","Bash(terraform state list*)","Bash(terraform state show*)",
      "Bash(node --version*)","Bash(python --version*)","Bash(python -m pytest*)",
      "Bash(python -m pip list*)","Bash(mise *)","Bash(ls*)","Bash(pwd)","Bash(echo *)",
      "Bash(wc *)","Bash(sort *)","Bash(uniq *)","Bash(cut *)","Bash(tr *)",
      "Bash(mkdir *)","Bash(touch *)","Bash(find *)","Bash(grep *)","Bash(rg *)",
      "Bash(fd *)","Bash(jq *)","Bash(yq *)","Bash(diff *)","Bash(file *)",
      "Bash(stat *)","Bash(which *)","Bash(date*)","Bash(printf *)","Bash(basename *)",
      "Bash(dirname *)","Bash(realpath *)","Bash(true*)","Bash(false*)","Bash(test *)",
      "Bash([ *)"
    ],
    "ask": [
      "Bash(nix *)","Bash(nix-store *)","Bash(gh *)","Bash(npm install*)",
      "Bash(pnpm install*)","Bash(yarn install*)","Bash(bun install*)","Bash(codex *)",
      "Bash(git push*)","Bash(npm publish*)","Bash(gh pr merge*)","Bash(git rebase*)",
      "Bash(git merge*)","Bash(git checkout*)","Bash(git restore*)","Bash(rm *)",
      "Bash(mv *)","Bash(cp *)","Bash(chmod *)","Bash(terraform apply*)",
      "Bash(terraform destroy*)","Bash(terraform import*)","Bash(sed *)","Bash(awk *)",
      "Bash(xargs *)","Bash(tee *)","Bash(make *)","Bash(make)","Bash(node *)",
      "Bash(python *)","Bash(cargo run*)"
    ],
    "deny": [
      "Bash(sudo *)","Bash(rm -rf /)","Bash(rm -rf /*)","Bash(rm -rf ~*)",
      "Bash(rm -fr *)","Bash(mkfs *)","Bash(dd *)","Bash(diskutil erase*)",
      "Bash(shutdown *)","Bash(reboot*)","Bash(bash*)","Bash(sh *)","Bash(sh)",
      "Bash(zsh*)","Bash(dash*)","Bash(eval *)","Bash(exec *)","Bash(source *)",
      "Bash(curl *)","Bash(wget *)","Bash(nc *)","Bash(ncat *)","Bash(telnet *)",
      "Bash(scp *)","Bash(scp)","Bash(rsync *)","Bash(rsync)","Bash(sftp *)",
      "Bash(sftp)","Bash(ftp *)","Bash(ftp)","Bash(ssh *)","Bash(ssh)",
      "Bash(* .env*)","Bash(* ~/.ssh/*)","Bash(* ~/.aws/*)","Bash(* ~/.config/gh/*)",
      "Bash(* ~/.git-credentials)","Bash(* ~/.netrc)","Bash(* ~/.npmrc)",
      "Bash(chmod 777 *)","Bash(chmod -R 777 *)","Bash(chmod 0777 *)",
      "Bash(chmod a+rwx *)","Bash(chown *)","Bash(chgrp *)",
      "Bash(git push --force*)","Bash(git push * --force*)","Bash(git push -f *)",
      "Bash(git push * -f *)","Bash(git reset --hard*)","Bash(git clean *)",
      "Bash(git checkout -f *)","Bash(git checkout -- .)","Bash(git switch -f *)",
      "Bash(git branch -D *)","Bash(git tag -d *)","Bash(git reflog expire*)",
      "Bash(git restore .)","Bash(git restore --worktree .)"
    ]
  }
}
SETTINGS_EOF
  )

  if [[ -f "$settings_file" ]] && command -v jq &>/dev/null; then
    echo "    Merging with existing settings.json"
    local existing
    existing=$(cat "$settings_file")
    if echo "$existing" | jq --argjson new "$new_settings" '
      ($new.permissions.allow // []) as $new_allow |
      (.permissions.allow // []) as $old_allow |
      ($old_allow + $new_allow | unique) as $merged_allow |
      . * $new |
      .permissions.allow = $merged_allow
    ' >"${settings_file}.tmp"; then
      mv "${settings_file}.tmp" "$settings_file"
    else
      echo "    Warning: existing settings.json is invalid or could not be merged; overwriting with new settings."
      rm -f "${settings_file}.tmp"
      echo "$new_settings" >"$settings_file"
    fi
  else
    echo "    Writing new settings.json"
    echo "$new_settings" >"$settings_file"
  fi
}

# ── deploy_codex_rules ────────────────────────────────────────
# Write Codex CLI rules to ~/.codex/rules/nix-managed.rules.
# Uses cat > (overwrite, not append) for idempotency.
deploy_codex_rules() {
  echo "==> Codex CLI rules"
  cat >"${HOME_DIR}/.codex/rules/nix-managed.rules" <<'CODEX_EOF'
# ── allow ──
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
prefix_rule(pattern=["git", "grep"], decision="allow")
prefix_rule(pattern=["git", "ls-tree"], decision="allow")
prefix_rule(pattern=["git", "for-each-ref"], decision="allow")
prefix_rule(pattern=["git", "merge-base"], decision="allow")
prefix_rule(pattern=["git", "config", "--get"], decision="allow")
prefix_rule(pattern=["git", "config", "--list"], decision="allow")
prefix_rule(pattern=["gh", "pr", "view"], decision="allow")
prefix_rule(pattern=["gh", "pr", "list"], decision="allow")
prefix_rule(pattern=["gh", "pr", "diff"], decision="allow")
prefix_rule(pattern=["gh", "pr", "checks"], decision="allow")
prefix_rule(pattern=["gh", "pr", "status"], decision="allow")
prefix_rule(pattern=["gh", "run", "list"], decision="allow")
prefix_rule(pattern=["gh", "run", "view"], decision="allow")
prefix_rule(pattern=["gh", "issue", "view"], decision="allow")
prefix_rule(pattern=["gh", "issue", "list"], decision="allow")
prefix_rule(pattern=["gh", "repo", "view"], decision="allow")
prefix_rule(pattern=["gh", "release", "list"], decision="allow")
prefix_rule(pattern=["gh", "release", "view"], decision="allow")
prefix_rule(pattern=["npm", "--version"], decision="allow")
prefix_rule(pattern=["npm", "help"], decision="allow")
prefix_rule(pattern=["npm", "run"], decision="allow")
prefix_rule(pattern=["npm", "test"], decision="allow")
prefix_rule(pattern=["npm", "ci"], decision="allow")
prefix_rule(pattern=["npm", "ls"], decision="allow")
prefix_rule(pattern=["npm", "outdated"], decision="allow")
prefix_rule(pattern=["npm", "info"], decision="allow")
prefix_rule(pattern=["npm", "view"], decision="allow")
prefix_rule(pattern=["pnpm", "--version"], decision="allow")
prefix_rule(pattern=["pnpm", "help"], decision="allow")
prefix_rule(pattern=["pnpm", "run"], decision="allow")
prefix_rule(pattern=["pnpm", "test"], decision="allow")
prefix_rule(pattern=["pnpm", "ls"], decision="allow")
prefix_rule(pattern=["pnpm", "why"], decision="allow")
prefix_rule(pattern=["yarn", "--version"], decision="allow")
prefix_rule(pattern=["yarn", "help"], decision="allow")
prefix_rule(pattern=["yarn", "run"], decision="allow")
prefix_rule(pattern=["yarn", "test"], decision="allow")
prefix_rule(pattern=["yarn", "why"], decision="allow")
prefix_rule(pattern=["bun", "--version"], decision="allow")
prefix_rule(pattern=["bun", "help"], decision="allow")
prefix_rule(pattern=["bun", "run"], decision="allow")
prefix_rule(pattern=["bun", "test"], decision="allow")
prefix_rule(pattern=["nix", "--version"], decision="allow")
prefix_rule(pattern=["nix", "help"], decision="allow")
prefix_rule(pattern=["nix", "flake", "check"], decision="allow")
prefix_rule(pattern=["nix", "flake", "show"], decision="allow")
prefix_rule(pattern=["nix", "flake", "metadata"], decision="allow")
prefix_rule(pattern=["nix", "path-info"], decision="allow")
prefix_rule(pattern=["shellcheck"], decision="allow")
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
prefix_rule(pattern=["terraform", "test"], decision="allow")
prefix_rule(pattern=["terraform", "version"], decision="allow")
prefix_rule(pattern=["snow", "sql"], decision="prompt")
prefix_rule(pattern=["snow", "object", "list"], decision="allow")
prefix_rule(pattern=["snow", "object", "describe"], decision="allow")
prefix_rule(pattern=["snow", "connection", "list"], decision="allow")
prefix_rule(pattern=["snow", "connection", "test"], decision="allow")
prefix_rule(pattern=["snow", "stage", "list-files"], decision="allow")
prefix_rule(pattern=["node", "--version"], decision="allow")
prefix_rule(pattern=["node", "--help"], decision="allow")
prefix_rule(pattern=["python", "--version"], decision="allow")
prefix_rule(pattern=["python", "-V"], decision="allow")
prefix_rule(pattern=["python", "-m", "pytest"], decision="allow")
prefix_rule(pattern=["python", "-m", "unittest"], decision="allow")
prefix_rule(pattern=["python", "-m", "compileall"], decision="allow")
prefix_rule(pattern=["python", "-m", "pip", "--version"], decision="allow")
prefix_rule(pattern=["python", "-m", "pip", "list"], decision="allow")
prefix_rule(pattern=["mise"], decision="allow")
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
# ── prompt ──
prefix_rule(pattern=["nix", "build"], decision="prompt")
prefix_rule(pattern=["nix", "run"], decision="prompt")
prefix_rule(pattern=["nix", "develop"], decision="prompt")
prefix_rule(pattern=["nix", "shell"], decision="prompt")
prefix_rule(pattern=["nix", "fmt"], decision="prompt")
prefix_rule(pattern=["nix", "eval"], decision="prompt")
prefix_rule(pattern=["nix", "flake", "update"], decision="prompt")
prefix_rule(pattern=["nix", "flake", "lock"], decision="prompt")
prefix_rule(pattern=["nix", "profile"], decision="prompt")
prefix_rule(pattern=["nix", "registry"], decision="prompt")
prefix_rule(pattern=["nix", "copy"], decision="prompt")
prefix_rule(pattern=["nix", "store"], decision="prompt")
prefix_rule(pattern=["nix", "daemon"], decision="prompt")
prefix_rule(pattern=["nix", "upgrade-nix"], decision="prompt")
prefix_rule(pattern=["nix-store"], decision="prompt")
prefix_rule(pattern=["gh", "api"], decision="prompt")
prefix_rule(pattern=["gh", "auth"], decision="prompt")
prefix_rule(pattern=["gh", "pr", "create"], decision="prompt")
prefix_rule(pattern=["gh", "pr", "edit"], decision="prompt")
prefix_rule(pattern=["gh", "pr", "checkout"], decision="prompt")
prefix_rule(pattern=["gh", "pr", "comment"], decision="prompt")
prefix_rule(pattern=["gh", "pr", "review"], decision="prompt")
prefix_rule(pattern=["gh", "pr", "close"], decision="prompt")
prefix_rule(pattern=["gh", "pr", "reopen"], decision="prompt")
prefix_rule(pattern=["gh", "issue", "create"], decision="prompt")
prefix_rule(pattern=["gh", "issue", "edit"], decision="prompt")
prefix_rule(pattern=["gh", "issue", "comment"], decision="prompt")
prefix_rule(pattern=["gh", "issue", "close"], decision="prompt")
prefix_rule(pattern=["gh", "issue", "reopen"], decision="prompt")
prefix_rule(pattern=["gh", "repo", "create"], decision="prompt")
prefix_rule(pattern=["gh", "repo", "edit"], decision="prompt")
prefix_rule(pattern=["gh", "repo", "delete"], decision="prompt")
prefix_rule(pattern=["gh", "repo", "fork"], decision="prompt")
prefix_rule(pattern=["gh", "release", "create"], decision="prompt")
prefix_rule(pattern=["gh", "release", "delete"], decision="prompt")
prefix_rule(pattern=["gh", "release", "upload"], decision="prompt")
prefix_rule(pattern=["gh", "workflow", "run"], decision="prompt")
prefix_rule(pattern=["gh", "run", "cancel"], decision="prompt")
prefix_rule(pattern=["gh", "run", "rerun"], decision="prompt")
prefix_rule(pattern=["gh", "run", "delete"], decision="prompt")
prefix_rule(pattern=["npm", "install"], decision="prompt")
prefix_rule(pattern=["npm", "update"], decision="prompt")
prefix_rule(pattern=["npm", "uninstall"], decision="prompt")
prefix_rule(pattern=["npm", "exec"], decision="prompt")
prefix_rule(pattern=["npx"], decision="prompt")
prefix_rule(pattern=["pnpm", "install"], decision="prompt")
prefix_rule(pattern=["pnpm", "update"], decision="prompt")
prefix_rule(pattern=["pnpm", "remove"], decision="prompt")
prefix_rule(pattern=["pnpm", "dlx"], decision="prompt")
prefix_rule(pattern=["yarn", "install"], decision="prompt")
prefix_rule(pattern=["yarn", "add"], decision="prompt")
prefix_rule(pattern=["yarn", "remove"], decision="prompt")
prefix_rule(pattern=["yarn", "dlx"], decision="prompt")
prefix_rule(pattern=["bun", "install"], decision="prompt")
prefix_rule(pattern=["bun", "add"], decision="prompt")
prefix_rule(pattern=["bun", "remove"], decision="prompt")
prefix_rule(pattern=["bunx"], decision="prompt")
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
prefix_rule(pattern=["treefmt"], decision="prompt")
prefix_rule(pattern=["nixfmt"], decision="prompt")
prefix_rule(pattern=["prettier"], decision="prompt")
prefix_rule(pattern=["shfmt"], decision="prompt")
prefix_rule(pattern=["make", "clean"], decision="prompt")
prefix_rule(pattern=["make", "install"], decision="prompt")
prefix_rule(pattern=["make", "deploy"], decision="prompt")
prefix_rule(pattern=["make", "release"], decision="prompt")
prefix_rule(pattern=["make", "publish"], decision="prompt")
prefix_rule(pattern=["make", "destroy"], decision="prompt")
prefix_rule(pattern=["make", "apply"], decision="prompt")
prefix_rule(pattern=["node", "-e"], decision="prompt")
prefix_rule(pattern=["node", "--eval"], decision="prompt")
prefix_rule(pattern=["python", "-c"], decision="prompt")
prefix_rule(pattern=["python", "-"], decision="prompt")
prefix_rule(pattern=["python", "-m", "pip", "install"], decision="prompt")
prefix_rule(pattern=["python", "-m", "pip", "uninstall"], decision="prompt")
prefix_rule(pattern=["cargo", "run"], decision="prompt")
# ── forbidden ──
prefix_rule(pattern=["snow", "stage", "copy"], decision="forbidden")
prefix_rule(pattern=["snow", "object", "create"], decision="forbidden")
prefix_rule(pattern=["snow", "object", "drop"], decision="forbidden")
prefix_rule(pattern=["nix", "store", "delete"], decision="forbidden")
prefix_rule(pattern=["nix-store", "--delete"], decision="forbidden")
prefix_rule(pattern=["nix-collect-garbage"], decision="forbidden")
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
}
