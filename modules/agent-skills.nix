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
    if pkgs.stdenv.isDarwin then "/Users/${username}"
    else if username == "root" then "/root"
    else "/home/${username}";

  # エージェント関連ファイルのベースパス
  agentBasePath = ../config/agents;

  # デプロイ対象のエージェント定義（config/agents/definitions/ 配下）
  agentDefinitions = [
    "architect"
    "code-reviewer"
    "doc-search"
    "doc-updater"
    "planner"
    "python-reviewer"
    "security-reviewer"
    "steering-research"
    "tdd-guide"
    "terraform-reviewer"
  ];

  # デプロイ対象のコマンド（config/agents/commands/ 配下）
  agentCommands = [
    "orchestrate"
  ];

  # 名前リストから home.file エントリを生成するヘルパー
  # パス型を維持するために basePath + 文字列結合を使用
  mkAgentEntries = names: destDir: srcDir:
    builtins.listToAttrs (map (name: {
      name = ".claude/${destDir}/${name}.md";
      value = { source = agentBasePath + "/${srcDir}/${name}.md"; };
    }) names);
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

  # エージェント定義・コマンド・ルール・スクリプトのデプロイ
  home.file = (mkAgentEntries agentDefinitions "agents" "definitions")
           // (mkAgentEntries agentCommands "commands" "commands") # srcDir = destDir: config/agents/commands/ → .claude/commands/
           // {
    # ルール（起動時に全て読み込まれ、スキルの発動トリガーとして機能する）
    ".claude/rules/skill-triggers.md".source =
      ../config/agents/rules/skill-triggers.md;
    # スクリプト（executable 属性が必要なため個別定義）
    ".claude/scripts/statusline.sh" = {
      source = ../config/agents/scripts/statusline.sh;
      executable = true;
    };
    # Claude Code Web 用セットアップスクリプト（任意リポジトリから参照可能）
    ".claude/scripts/setup-nix-web.sh" = {
      source = ../setup-nix-web.sh;
      executable = true;
    };
    # Codex CLI ルール（~/.codex/rules/nix-managed.rules）
    # default.rules はセッション中に自動追記されるため別ファイルで管理
    ".codex/rules/nix-managed.rules".text = ''
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

    # Build tools（safe targets のみ）
    prefix_rule(pattern=["make", "test"], decision="allow")
    prefix_rule(pattern=["make", "build"], decision="allow")
    prefix_rule(pattern=["make", "check"], decision="allow")
    # make clean は prompt（ファイル削除を伴うため）
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

    # Runtime（バージョン確認・テスト等）
    prefix_rule(pattern=["node", "--version"], decision="allow")
    prefix_rule(pattern=["python", "--version"], decision="allow")
    prefix_rule(pattern=["python", "-m", "pytest"], decision="allow")
    prefix_rule(pattern=["python", "-m", "pip", "list"], decision="allow")
    prefix_rule(pattern=["mise"], decision="allow")

    # Shell utilities（読み取り・変換系）
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
    # sed, awk は prompt に移動（F-01: ファイル変更プリミティブを持つ）
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
    # xargs, tee は prompt に移動（F-02/F-03: コマンド増幅・ファイル書き込み）
    prefix_rule(pattern=["true"], decision="allow")
    prefix_rule(pattern=["false"], decision="allow")
    prefix_rule(pattern=["test"], decision="allow")
    prefix_rule(pattern=["["], decision="allow")
    # chmod +x は prompt に移動（F-NEW-05: chmod の ask バイパス防止）
    # ── prompt: 確認が必要 ──

    # Nix / GitHub CLI
    prefix_rule(pattern=["nix"], decision="prompt")
    prefix_rule(pattern=["nix-store"], decision="prompt")
    prefix_rule(pattern=["gh"], decision="prompt")

    # Package install / agent invocation
    prefix_rule(pattern=["npm", "install"], decision="prompt")
    prefix_rule(pattern=["pnpm", "install"], decision="prompt")
    prefix_rule(pattern=["yarn", "install"], decision="prompt")
    prefix_rule(pattern=["bun", "install"], decision="prompt")
    prefix_rule(pattern=["codex"], decision="prompt")

    # リモート影響
    prefix_rule(pattern=["git", "push"], decision="prompt")
    prefix_rule(pattern=["npm", "publish"], decision="prompt")
    prefix_rule(pattern=["gh", "pr", "merge"], decision="prompt")
    # 破壊の可能性がある操作
    prefix_rule(pattern=["git", "rebase"], decision="prompt")
    prefix_rule(pattern=["git", "merge"], decision="prompt")
    prefix_rule(pattern=["git", "checkout"], decision="prompt")
    prefix_rule(pattern=["git", "restore"], decision="prompt")
    prefix_rule(pattern=["rm"], decision="prompt")
    prefix_rule(pattern=["mv"], decision="prompt")
    prefix_rule(pattern=["cp"], decision="prompt")
    prefix_rule(pattern=["chmod"], decision="prompt")
    # Terraform 変更適用
    prefix_rule(pattern=["terraform", "apply"], decision="prompt")
    prefix_rule(pattern=["terraform", "destroy"], decision="prompt")
    prefix_rule(pattern=["terraform", "import"], decision="prompt")
    # ファイル変更・コマンド増幅（F-01/F-02/F-03）
    prefix_rule(pattern=["sed"], decision="prompt")
    prefix_rule(pattern=["awk"], decision="prompt")
    prefix_rule(pattern=["xargs"], decision="prompt")
    prefix_rule(pattern=["tee"], decision="prompt")
    # ビルドツール汎用（F-NEW-03）
    prefix_rule(pattern=["make"], decision="prompt")
    # 汎用 runtime 実行
    prefix_rule(pattern=["node"], decision="prompt")
    prefix_rule(pattern=["python"], decision="prompt")
    prefix_rule(pattern=["cargo", "run"], decision="prompt")

    # ── forbidden: 完全ブロック ──

    # システム破壊
    prefix_rule(pattern=["sudo"], decision="forbidden")
    prefix_rule(pattern=["rm", "-rf", "/"], decision="forbidden")
    prefix_rule(pattern=["rm", "-rf", "~"], decision="forbidden")
    prefix_rule(pattern=["rm", "-fr"], decision="forbidden")
    prefix_rule(pattern=["mkfs"], decision="forbidden")
    prefix_rule(pattern=["dd"], decision="forbidden")
    prefix_rule(pattern=["diskutil", "erase"], decision="forbidden")
    prefix_rule(pattern=["shutdown"], decision="forbidden")
    prefix_rule(pattern=["reboot"], decision="forbidden")
    # シェルインタプリタ（F-10: 任意コード実行バイパス防止）
    # bare invocation（bash script.sh 等）も含めて全てブロック
    prefix_rule(pattern=["bash"], decision="forbidden")
    prefix_rule(pattern=["sh"], decision="forbidden")
    prefix_rule(pattern=["zsh"], decision="forbidden")
    prefix_rule(pattern=["dash"], decision="forbidden")
    prefix_rule(pattern=["eval"], decision="forbidden")
    prefix_rule(pattern=["exec"], decision="forbidden")
    # source はシェルビルトインのため top-level 呼び出しのみブロック（スクリプト内部の source は対象外）
    prefix_rule(pattern=["source"], decision="forbidden")
    # 外部送信系
    prefix_rule(pattern=["curl"], decision="forbidden")
    prefix_rule(pattern=["wget"], decision="forbidden")
    prefix_rule(pattern=["nc"], decision="forbidden")
    prefix_rule(pattern=["ncat"], decision="forbidden")
    prefix_rule(pattern=["telnet"], decision="forbidden")
    # ファイル転送（F-13: データ漏洩防止）
    prefix_rule(pattern=["scp"], decision="forbidden")
    prefix_rule(pattern=["rsync"], decision="forbidden")
    prefix_rule(pattern=["sftp"], decision="forbidden")
    prefix_rule(pattern=["ftp"], decision="forbidden")
    prefix_rule(pattern=["ssh"], decision="forbidden")
    # パーミッション破壊
    prefix_rule(pattern=["chmod", "777"], decision="forbidden")
    prefix_rule(pattern=["chmod", "-R", "777"], decision="forbidden")
    prefix_rule(pattern=["chmod", "0777"], decision="forbidden")
    prefix_rule(pattern=["chmod", "a+rwx"], decision="forbidden")
    prefix_rule(pattern=["chown"], decision="forbidden")
    prefix_rule(pattern=["chgrp"], decision="forbidden")
    # Git 破壊的操作
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
    '';
    # Claude Code グローバル設定（~/.claude/settings.json）
    ".claude/settings.json".text = builtins.toJSON {
    # Claude Code Web 用 SessionStart hook（HM 適用後は全リポジトリで自動発火）
    # NOTE: このグローバル hook は HM 適用後にのみ有効。初回ブートストラップには
    # リポジトリレベルの .claude/settings.json（curl フォールバック付き）が必要。
    hooks = {
      SessionStart = [{
        matcher = "startup|resume";
        hooks = [{
          type = "command";
          command = "[ \"$CLAUDE_CODE_REMOTE\" = \"true\" ] && ~/.claude/scripts/setup-nix-web.sh >/dev/null || echo '[setup-nix-web] hook failed' >&2";
          timeout = 300;
        }];
      }];
    };
    statusLine = {
      type = "command";
      command = "~/.claude/scripts/statusline.sh";
    };
    enableAllProjectMcpServers = false;
    permissions = {
      disableBypassPermissionsMode = "disable";
      additionalDirectories = [
        "~/.local/state/steering"
      ];
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
        # GitHub CLI（read-only 系のみ）
        "Bash(gh pr view*)"
        "Bash(gh run list*)"
        "Bash(gh run view*)"
        "Bash(gh issue view*)"
        # Package managers（read / build / test）
        "Bash(npm run *)"
        "Bash(npm test*)"
        "Bash(npm ci*)"
        "Bash(npm ls*)"
        "Bash(npm outdated*)"
        "Bash(npm info*)"
        "Bash(pnpm run *)"
        "Bash(pnpm test*)"
        "Bash(pnpm ls*)"
        "Bash(yarn run *)"
        "Bash(yarn test*)"
        "Bash(bun run *)"
        "Bash(bun test*)"
        # Build tools（safe targets のみ）
        "Bash(make test*)"
        "Bash(make build*)"
        "Bash(make check*)"
        # make clean は ask（ファイル削除を伴うため）
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
        "Bash(python --version*)"
        "Bash(python -m pytest*)"
        "Bash(python -m pip list*)"
        "Bash(mise *)"
        # Shell utilities（読み取り・変換系）
        # cat/head/tail は Read ツールで代替する
        "Bash(ls*)"
        "Bash(pwd)"
        "Bash(echo *)"
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
        # sed, awk は ask に移動（F-01）
        "Bash(jq *)"
        "Bash(yq *)"
        "Bash(diff *)"
        "Bash(file *)"
        "Bash(stat *)"
        "Bash(which *)"
        "Bash(date*)"
        "Bash(printf *)"
        "Bash(basename *)"
        "Bash(dirname *)"
        "Bash(realpath *)"
        # xargs, tee は ask に移動（F-02/F-03）
        "Bash(true*)"
        "Bash(false*)"
        "Bash(test *)"
        "Bash([ *)"
        # chmod +x は ask に移動（F-NEW-05）
      ];
      # ── 確認が必要 ──
      ask = [
        # Nix / GitHub CLI
        "Bash(nix *)"
        "Bash(nix-store *)"
        "Bash(gh *)"
        # Package install / agent invocation
        "Bash(npm install*)"
        "Bash(pnpm install*)"
        "Bash(yarn install*)"
        "Bash(bun install*)"
        "Bash(codex *)"
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
        # ファイル変更・コマンド増幅（F-01/F-02/F-03）
        "Bash(sed *)"
        "Bash(awk *)"
        "Bash(xargs *)"
        "Bash(tee *)"
        # ビルドツール汎用（F-NEW-03: bare make 含む）
        "Bash(make *)"
        "Bash(make)"
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
        # シェルインタプリタ（F-10: 任意コード実行バイパス防止）
        # bare invocation（bash 単体）も含めて全てブロック
        "Bash(bash*)"
        "Bash(sh *)"
        "Bash(sh)"
        "Bash(zsh*)"
        "Bash(dash*)"
        "Bash(eval *)"
        "Bash(exec *)"
        # source はシェルビルトインのため top-level 呼び出しのみブロック
        "Bash(source *)"
        # 外部送信系
        "Bash(curl *)"
        "Bash(wget *)"
        "Bash(nc *)"
        "Bash(ncat *)"
        "Bash(telnet *)"
        # ファイル転送（F-13: データ漏洩防止）
        "Bash(scp *)"
        "Bash(scp)"
        "Bash(rsync *)"
        "Bash(rsync)"
        "Bash(sftp *)"
        "Bash(sftp)"
        "Bash(ftp *)"
        "Bash(ftp)"
        "Bash(ssh *)"
        "Bash(ssh)"
        # 機密パス
        "Bash(* .env*)"
        "Bash(* ~/.ssh/*)"
        "Bash(* ~/.aws/*)"
        "Bash(* ~/.config/gh/*)"
        "Bash(* ~/.git-credentials)"
        "Bash(* ~/.netrc)"
        "Bash(* ~/.npmrc)"
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
  };  # end of builtins.toJSON (settings.json)
  };  # end of home.file
}
