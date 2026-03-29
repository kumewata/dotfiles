{
  config,
  pkgs,
  username,
  ...
}:

{
  home.packages = [
    pkgs.treefmt
    pkgs.pre-commit
    pkgs.nixfmt
    pkgs.shfmt
    pkgs.shellcheck
    pkgs.prettier
  ];
}
