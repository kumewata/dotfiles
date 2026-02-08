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
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      system = "aarch64-darwin"; # Apple Silicon Mac
      pkgs = nixpkgs.legacyPackages.${system};

    in {
      homeConfigurations."kumewataru" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # 実行時のユーザー名を取得（--impure フラグが必要、遅延評価される）
        extraSpecialArgs = { username = builtins.getEnv "USER"; };

        modules = [ ./home.nix ];
      };

      # 互換性のためのエイリアス
      homeConfigurations."default" = self.homeConfigurations."kumewataru";
    };
}
