# dotfiles

macOS (Apple Silicon) の開発環境を **Nix Flakes** + **Home Manager** で宣言的に管理する dotfiles リポジトリ。

シェル設定、CLI ツール、エイリアスなどを Nix の設定ファイルで一元管理し、`hms` コマンド一つで環境を再現できる。ユーザー名は `$USER` 環境変数から動的に解決されるため、複数の Mac デバイスで同じ設定をそのまま利用可能。

## 前提条件

- macOS (Apple Silicon / aarch64-darwin)
- Git

## セットアップ

### 1. Nix のインストール

[Determinate Nix Installer](https://github.com/DeterminateSystems/nix-installer) を使用する（Flakes がデフォルトで有効になる）。

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

インストール後、ターミナルを再起動して `nix --version` で動作確認する。

### 2. リポジトリのクローン

```bash
git clone https://github.com/kumewata/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

### 3. 設定の適用

```bash
nix run github:nix-community/home-manager/release-25.11 -- switch --impure --flake .#default
```

適用後、ターミナルを再起動すると Zsh の設定やエイリアスが有効になる。

## 日常の使い方

```bash
# 設定ファイルを編集した後、変更を適用する（エイリアス）
hms

# Flake の入力（nixpkgs 等）を最新に更新する
nix flake update
```

## リポジトリ構成

```
.
├── flake.nix              # Flake エントリポイント（nixpkgs unstable + Home Manager）
├── flake.lock             # 依存のロックファイル
├── home.nix               # Home Manager メイン設定（モジュール読み込み・ユーザー情報）
├── modules/
│   ├── packages.nix       # CLI ツール（ripgrep, fd 等）
│   ├── shell.nix          # Zsh 設定（Oh My Zsh, エイリアス, initExtra）
│   └── claude-skills.nix  # Claude Code スキルのシンボリックリンク設定
├── config/
│   └── agents/
│       └── skills/        # Claude Code スキル定義ファイル群
├── .zshrc                 # レガシー Zsh 設定（shell.nix へ移行中）
└── CLAUDE.md              # Claude Code 向けプロジェクト指示
```

## カスタマイズ

### パッケージを追加する

`modules/packages.nix` の `home.packages` リストにパッケージを追加する。

```nix
home.packages = [
  pkgs.ripgrep
  pkgs.fd
  pkgs.jq       # 追加
];
```

パッケージは [NixOS Search](https://search.nixos.org/packages) で検索できる。

### シェルエイリアスを追加する

`modules/shell.nix` の `home.shellAliases` にエントリを追加する。

```nix
home.shellAliases = {
  hms = "nix run github:nix-community/home-manager/release-25.11 -- switch --impure --flake .#default";
  ll = "ls -l";
  # 追加
  la = "ls -la";
};
```

### モジュールを追加する

1. `modules/` に新しい `.nix` ファイルを作成する
2. `home.nix` の `imports` に追加する

```nix
imports = [
  ./modules/packages.nix
  ./modules/shell.nix
  ./modules/claude-skills.nix
  ./modules/new-module.nix   # 追加
];
```

## シェルエイリアス一覧

| エイリアス | コマンド |
|---|---|
| `hms` | `nix run github:nix-community/home-manager/release-25.11 -- switch --impure --flake .#default` |
| `ll` | `ls -l` |
| `co` | `git checkout` |
| `br` | `git branch` |
| `st` | `git status` |
| `gif` | `git diff` |
| `gifs` | `git diff --staged` |
| `gil` | `git pull` |
| `cm` | `git commit` |
| `pn` | `pnpm` |
