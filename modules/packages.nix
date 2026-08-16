{
  config,
  pkgs,
  username,
  ...
}:

{
  # ユーザー環境にインストールするパッケージのリスト
  home.packages = [
    pkgs.ripgrep # Claude Codeがファイルを高速検索するために使用 🔍
    pkgs.fd # シンプルで高速なファイル検索ツール 📂
    pkgs.gh # GitHub CLI
    pkgs.gws # Google Workspace CLI
    pkgs.jq # JSON processor (hooks/scripts で使用)
    pkgs.herdr # ターミナル常駐のエージェント multiplexer 🐑
    pkgs.mise # 開発ツールのバージョン管理（Homebrew 版は aqua registry の取得に失敗するため Nix 管理へ）
    pkgs.hello # 動作確認用のテストツール 👋
  ];
}
