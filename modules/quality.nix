{ pkgs, ... }:

{
  home.packages = [
    pkgs.pre-commit
    pkgs.treefmt
    pkgs.nixfmt
    pkgs.nodePackages.prettier
    pkgs.shfmt
    pkgs.shellcheck
  ];
}
