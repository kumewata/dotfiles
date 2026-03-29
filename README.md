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
nix run --impure .#switch
```

`switch` app は `builtins.getEnv "USER"` を使うため、`--impure` が必要。適用後、ターミナルを再起動すると Zsh の設定やエイリアスが有効になる。

### 4. formatter / pre-commit の初期化（推奨）

`hms` 適用後は `treefmt` と `pre-commit` が利用できる。コミット前チェックを有効にするため、初回のみ hook をインストールする。`sensitive-patterns.txt` はローカル専用のため、sample から作成する。

```bash
pre-commit install
cp .githooks/sensitive-patterns.sample.txt .githooks/sensitive-patterns.txt
```

必要に応じて `.githooks/sensitive-patterns.txt` を編集して、組織固有のパターンを追加する。

### 5. Git SSH 署名の初期化（任意）

この dotfiles では、当面 `~/.ssh/id_ed25519.pub` を Git の SSH 署名鍵として参照する。秘密鍵そのものは管理せず、Git 側の設定だけを反映する。

初回は GitHub の `SSH signing keys` に公開鍵を登録してから `hms` を実行する。

```bash
# 公開鍵を確認する
cat ~/.ssh/id_ed25519.pub

# 設定適用後に署名設定を確認する
git config --get gpg.format
git config --get user.signingKey
git config --get gpg.ssh.allowedSignersFile
```

署名付き commit の確認:

```bash
git log --show-signature -1
```

この設定は Git SSH 署名だけを先に導入するもので、`programs.git` の本格移行とは別タスクとして扱う。

## 日常の使い方

```bash
# 設定ファイルを編集した後、変更を適用する
nix run --impure .#switch

# リポジトリ全体を整形する
nix fmt

# ローカル品質チェックを実行する
nix run .#check

# Flake の入力（nixpkgs 等）を最新に更新する
nix run .#update
```

既存の `hms` エイリアスは互換導線として残しているが、README 上の主導線は flake apps の `switch/check/update` とする。

## CI

GitHub Actions の `CI` workflow は、pull request と `main` への push で次を実行する。

- `nix flake check`
- `nix fmt -- --fail-on-change`
- `nix run .#check`

ローカルで CI 相当の確認をしたい場合は、少なくとも `nix fmt -- --fail-on-change` と `nix run .#check` を実行する。

## リポジトリ構成

```
.
├── .github/workflows/ci.yml # GitHub Actions の最小 CI
├── flake.nix              # Flake エントリポイント（nixpkgs unstable + Home Manager）
├── flake.lock             # 依存のロックファイル
├── home.nix               # Home Manager メイン設定（モジュール読み込み・ユーザー情報）
├── treefmt.toml           # treefmt の整形ルール
├── .pre-commit-config.yaml # pre-commit の hook 定義
├── modules/
│   ├── packages.nix       # CLI ツール（ripgrep, fd 等）
│   ├── quality.nix        # treefmt / pre-commit など品質基盤ツール
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
  hms = "nix run --impure github:nix-community/home-manager/release-25.11 -- switch --flake .#default";
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

`hms` は `nix run --impure .#switch` と同じ目的の互換エイリアス。

| エイリアス | コマンド                                                                                       |
| ---------- | ---------------------------------------------------------------------------------------------- |
| `hms`      | `nix run --impure github:nix-community/home-manager/release-25.11 -- switch --flake .#default` |
| `ll`       | `ls -l`                                                                                        |
| `co`       | `git checkout`                                                                                 |
| `br`       | `git branch`                                                                                   |
| `st`       | `git status`                                                                                   |
| `gif`      | `git diff`                                                                                     |
| `gifs`     | `git diff --staged`                                                                            |
| `gil`      | `git pull`                                                                                     |
| `cm`       | `git commit`                                                                                   |
| `pn`       | `pnpm`                                                                                         |
