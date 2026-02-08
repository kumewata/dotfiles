{ config, pkgs, username, ... }:

{
  # home.nix から移動してきた設定
  home.file.".claude/skills" = {
    source = ../config/agents/skills;
    recursive = true;
  };
}
