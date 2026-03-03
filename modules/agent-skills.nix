# Agent Skills の統一管理（Claude Code / OpenAI Codex）
# agent-skills-nix を使用して symlink-tree 構造でデプロイ
# cf. https://github.com/Kyure-A/agent-skills-nix
{
  inputs,
  pkgs,
  username,
  ...
}:
let
  homeDir =
    if pkgs.stdenv.isDarwin
    then "/Users/${username}"
    else "/home/${username}";
in
{
  imports = [
    inputs.agent-skills.homeManagerModules.default
  ];

  programs.agent-skills = {
    enable = true;

    # スキルソース（このリポジトリの config/agents/skills/）
    sources.local = {
      path = inputs.self;
      subdir = "config/agents/skills";
    };

    # 全スキルを有効化
    skills.enableAll = true;

    # デプロイ先
    targets = {
      # Claude Code: ~/.claude/skills/
      claude = {
        enable = true;
        structure = "symlink-tree";
      };
      # OpenAI Codex: ~/.codex/skills/
      codex = {
        enable = true;
        dest = "${homeDir}/.codex/skills";
        structure = "symlink-tree";
      };
    };

    # Codex が実行時に作成する .system/ ディレクトリを保護
    excludePatterns = [ "/.system" ];
  };

  # エージェント定義のデプロイ（~/.claude/agents/）
  home.file.".claude/agents/steering-research.md".source =
    ../config/agents/definitions/steering-research.md;
  home.file.".claude/agents/doc-search.md".source =
    ../config/agents/definitions/doc-search.md;

  # ルールのデプロイ（~/.claude/rules/）
  # Rules は起動時に全て読み込まれ、スキルの発動トリガーとして機能する
  home.file.".claude/rules/skill-triggers.md".source =
    ../config/agents/rules/skill-triggers.md;

  # スクリプトのデプロイ（~/.claude/scripts/）
  home.file.".claude/scripts/statusline.sh" = {
    source = ../config/agents/scripts/statusline.sh;
    executable = true;
  };

  # Claude Code グローバル設定（~/.claude/settings.json）
  home.file.".claude/settings.json".text = builtins.toJSON {
    statusLine = {
      type = "command";
      command = "~/.claude/scripts/statusline.sh";
    };
    permissions = {
      # ── 自動許可 ──
      allow = [
        # Non-Bash tools
        "Read"
        "Edit"
        "Write"
        "WebSearch"
        "WebFetch"
        "Agent"
        "Skill"
        "MCP"
        # Git（安全なサブコマンドのみ）
        "Bash(git status*)"
        "Bash(git diff*)"
        "Bash(git log*)"
        "Bash(git show*)"
        "Bash(git blame*)"
        "Bash(git branch*)"
        "Bash(git fetch*)"
        "Bash(git pull*)"
        "Bash(git add*)"
        "Bash(git commit*)"
        "Bash(git switch*)"
        "Bash(git stash*)"
        "Bash(git tag*)"
        "Bash(git remote*)"
        "Bash(git rev-parse*)"
        "Bash(git ls-files*)"
        "Bash(git shortlog*)"
        "Bash(git config --get*)"
        "Bash(git config --list*)"
        # Nix
        "Bash(nix *)"
        "Bash(nix-store *)"
        # GitHub CLI
        "Bash(gh *)"
        # Package managers（read / build / test）
        "Bash(npm run *)"
        "Bash(npm test*)"
        "Bash(npm install*)"
        "Bash(npm ci*)"
        "Bash(npm ls*)"
        "Bash(npm outdated*)"
        "Bash(npm info*)"
        "Bash(pnpm run *)"
        "Bash(pnpm test*)"
        "Bash(pnpm install*)"
        "Bash(pnpm ls*)"
        "Bash(yarn run *)"
        "Bash(yarn test*)"
        "Bash(yarn install*)"
        "Bash(bun run *)"
        "Bash(bun test*)"
        "Bash(bun install*)"
        # Build tools
        "Bash(make *)"
        "Bash(cargo build*)"
        "Bash(cargo test*)"
        "Bash(cargo check*)"
        "Bash(cargo clippy*)"
        "Bash(cargo fmt*)"
        "Bash(terraform init*)"
        "Bash(terraform plan*)"
        "Bash(terraform validate*)"
        "Bash(terraform fmt*)"
        "Bash(terraform show*)"
        "Bash(terraform output*)"
        "Bash(terraform state list*)"
        "Bash(terraform state show*)"
        # Runtime（バージョン確認・テスト等のみ）
        "Bash(node --version*)"
        "Bash(node -e *)"
        "Bash(node -p *)"
        "Bash(python --version*)"
        "Bash(python -c *)"
        "Bash(python -m pytest*)"
        "Bash(python -m pip list*)"
        "Bash(mise *)"
        # Shell utilities（読み取り・変換系）
        "Bash(ls*)"
        "Bash(pwd)"
        "Bash(echo *)"
        "Bash(cat *)"
        "Bash(head *)"
        "Bash(tail *)"
        "Bash(wc *)"
        "Bash(sort *)"
        "Bash(uniq *)"
        "Bash(cut *)"
        "Bash(tr *)"
        "Bash(mkdir *)"
        "Bash(touch *)"
        "Bash(find *)"
        "Bash(grep *)"
        "Bash(rg *)"
        "Bash(fd *)"
        "Bash(sed *)"
        "Bash(awk *)"
        "Bash(jq *)"
        "Bash(yq *)"
        "Bash(diff *)"
        "Bash(file *)"
        "Bash(stat *)"
        "Bash(which *)"
        "Bash(date*)"
        "Bash(env *)"
        "Bash(printf *)"
        "Bash(basename *)"
        "Bash(dirname *)"
        "Bash(realpath *)"
        "Bash(xargs *)"
        "Bash(tee *)"
        "Bash(true*)"
        "Bash(false*)"
        "Bash(test *)"
        "Bash([ *)"
        "Bash(chmod +x *)"
        "Bash(codex *)"
      ];
      # ── 確認が必要 ──
      ask = [
        # リモート影響
        "Bash(git push*)"
        "Bash(npm publish*)"
        "Bash(gh pr merge*)"
        # 破壊の可能性がある操作
        "Bash(git rebase*)"
        "Bash(git merge*)"
        "Bash(git checkout*)"
        "Bash(git restore*)"
        "Bash(rm *)"
        "Bash(mv *)"
        "Bash(cp *)"
        "Bash(chmod *)"
        # Terraform 変更適用
        "Bash(terraform apply*)"
        "Bash(terraform destroy*)"
        "Bash(terraform import*)"
        # 汎用 runtime 実行
        "Bash(node *)"
        "Bash(python *)"
        "Bash(cargo run*)"
      ];
      # ── 完全ブロック（deny は allow/ask より常に優先） ──
      deny = [
        # システム破壊
        "Bash(sudo *)"
        "Bash(rm -rf /)"
        "Bash(rm -rf /*)"
        "Bash(rm -rf ~*)"
        "Bash(rm -fr *)"
        "Bash(mkfs *)"
        "Bash(dd *)"
        "Bash(diskutil erase*)"
        "Bash(shutdown *)"
        "Bash(reboot*)"
        # パーミッション破壊
        "Bash(chmod 777 *)"
        "Bash(chmod -R 777 *)"
        "Bash(chmod 0777 *)"
        "Bash(chmod a+rwx *)"
        "Bash(chown *)"
        "Bash(chgrp *)"
        # Git 破壊的操作
        "Bash(git push --force*)"
        "Bash(git push * --force*)"
        "Bash(git push -f *)"
        "Bash(git push * -f *)"
        "Bash(git reset --hard*)"
        "Bash(git clean *)"
        "Bash(git checkout -f *)"
        "Bash(git checkout -- .)"
        "Bash(git switch -f *)"
        "Bash(git branch -D *)"
        "Bash(git tag -d *)"
        "Bash(git reflog expire*)"
        "Bash(git restore .)"
        "Bash(git restore --worktree .)"
      ];
    };
  };
}
