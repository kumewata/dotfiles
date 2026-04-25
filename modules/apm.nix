# Agent Package Manager (Microsoft) - PyInstaller bundled binary
#
# 公式リリース: https://github.com/microsoft/apm/releases
# nixpkgs に未収録のため、release tarball を fetchurl で取得して同梱。
# PyInstaller bundle なので strip / patchelf / fixup は無効化する。
#
# 更新手順:
#   1. https://github.com/microsoft/apm/releases から新バージョンを確認
#   2. version を更新
#   3. `nix-prefetch-url <URL>` で sha256 を取得して hashes に書き換え
#   4. `hms` で適用
{
  config,
  pkgs,
  lib,
  ...
}:
let
  version = "0.9.2";

  platform =
    if pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64 then
      "darwin-arm64"
    else if pkgs.stdenv.isDarwin && pkgs.stdenv.isx86_64 then
      "darwin-x86_64"
    else if pkgs.stdenv.isLinux && pkgs.stdenv.isAarch64 then
      "linux-arm64"
    else if pkgs.stdenv.isLinux && pkgs.stdenv.isx86_64 then
      "linux-x86_64"
    else
      throw "unsupported platform for apm";

  # platform ごとの sha256（追加 platform をサポートする場合は埋める）
  hashes = {
    "darwin-arm64" = "546ab17fc87d3aab569abd02f57dad616ced20fe92b241d1036cddafb70ce619";
  };

  apm = pkgs.stdenvNoCC.mkDerivation {
    pname = "apm";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/microsoft/apm/releases/download/v${version}/apm-${platform}.tar.gz";
      sha256 = hashes.${platform} or (throw "apm: sha256 not pinned for platform ${platform}");
    };

    sourceRoot = ".";

    dontConfigure = true;
    dontBuild = true;
    # PyInstaller bundle: 改変すると壊れるので fixup 系を全て無効化
    dontStrip = true;
    dontFixup = true;
    dontPatchELF = true;
    dontAutoPatchelf = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib $out/bin
      # apm-<platform>/ ディレクトリ全体を $out/lib/apm にコピー
      cp -r apm-${platform} $out/lib/apm
      # PyInstaller は実バイナリの位置から _MEIPASS を解決するため、symlink で OK
      ln -s $out/lib/apm/apm $out/bin/apm
      runHook postInstall
    '';

    meta = with lib; {
      description = "Agent Package Manager - npm-like dependency manager for AI agent configurations";
      homepage = "https://github.com/microsoft/apm";
      license = licenses.mit;
      platforms = [ "aarch64-darwin" ];
      mainProgram = "apm";
    };
  };
in
{
  home.packages = [ apm ];
}
