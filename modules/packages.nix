{ config, pkgs, username, ... }:

{
  # ユーザー環境にインストールするパッケージのリスト
  home.packages = [
    pkgs.ripgrep  # Claude Codeがファイルを高速検索するために使用 🔍
    pkgs.fd       # シンプルで高速なファイル検索ツール 📂
    pkgs.gh       # GitHub CLI
    pkgs.hello    # 動作確認用のテストツール 👋
  ];
}
