{ config, pkgs, username, ... }:

{
  # OpenAI Codex CLI 用のスキル設定
  # Claude Code と同じスキルファイルを ~/.codex/skills/ にデプロイ
  home.file.".codex/skills" = {
    source = ../config/agents/skills;
    recursive = true;
  };
}
