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

  outputs = { nixpkgs, home-manager, ... }:
    let
      # あなたのマシンの設定
      system = "aarch64-darwin"; # Apple Silicon Mac
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      homeConfigurations."kumewataru" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # home.nix を設定ファイルとして読み込む
        modules = [ ./home.nix ];
      };
    };
}

