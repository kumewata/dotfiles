{
  config,
  pkgs,
  username,
  ...
}:

{
  # モジュールの読み込み
  imports = [
    ./modules/agent-skills.nix
    ./modules/git.nix
    ./modules/launchd.nix
    ./modules/packages.nix
    ./modules/quality.nix
    ./modules/shell.nix
  ];

  # ユーザー情報の設定（extraSpecialArgs から受け取った username を使用）
  home.username = username;
  home.homeDirectory =
    if pkgs.stdenv.isDarwin then
      "/Users/${username}"
    else if username == "root" then
      "/root"
    else
      "/home/${username}";

  # Home Manager のバージョン互換性のための設定（変更不要）
  home.stateVersion = "25.11";

  # インストールしたいパッケージ
  home.packages = [
    pkgs.hello
  ];

  # Home Manager 自体を Home Manager で管理する設定
  programs.home-manager.enable = true;
}
