{
  description = "Home Manager configuration of kumewataru";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Agent Skills（Claude Code / Codex 等のスキル管理）
    agent-skills = {
      url = "github:Kyure-A/agent-skills-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, ... }:
    let
      # --impure で実行時のシステムを検出（デフォルトは aarch64-darwin）
      system = builtins.getEnv "NIX_SYSTEM"
        |> (s: if s == "" then "aarch64-darwin" else s);
      pkgs = nixpkgs.legacyPackages.${system};

      mkHome = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # 実行時のユーザー名を取得（--impure フラグが必要、遅延評価される）
        # inputs は agent-skills モジュールで使用
        extraSpecialArgs = {
          inherit inputs;
          username = builtins.getEnv "USER";
        };

        modules = [ ./home.nix ];
      };

    in {
      homeConfigurations."kumewataru" = mkHome;

      # 互換性のためのエイリアス
      homeConfigurations."default" = mkHome;
    };
}
