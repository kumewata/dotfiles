{ config, pkgs, ... }:

{
  # home.nix から移動してきた設定
  home.file.".claude/skills" = {
    source = ../skills-files;
    recursive = true;
  };
}
