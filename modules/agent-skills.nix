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
}
