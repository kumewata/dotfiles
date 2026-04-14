{ pkgs, ... }:

{
  home.packages = [
    pkgs.pre-commit
    pkgs.treefmt
    pkgs.nixfmt
    pkgs.prettier
    pkgs.shfmt
    pkgs.shellcheck
    pkgs.actionlint
    pkgs.ghalint
    pkgs.zizmor
  ];
}
