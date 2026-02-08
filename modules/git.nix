{ config, pkgs, username, ... }:

{
  home.file.".config/git/ignore".text = builtins.concatStringsSep "\n" [
    ".DS_Store"
    ".direnv/"
    ".env"
    "node_modules/"
    ".mcp.json"
    ".steering/"
    "**/.claude/settings.local.json"
  ] + "\n";
}
