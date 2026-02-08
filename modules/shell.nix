{ config, pkgs, username, ... }:

{
  programs.zsh = {
    enable = true;

    # Oh My Zsh 設定（.zshrc より）
    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [ "git" ];
    };

    # 追加の初期化スクリプト（.zshrc の User configuration 以下）
    initContent = ''
      # Add ~/.local/bin to PATH if it exists
      if [ -d "''$HOME/.local/bin" ]; then
        export PATH="''$HOME/.local/bin:''$PATH"
      fi

      # Initialize mise (version manager) if available
      if command -v mise >/dev/null 2>&1; then
        eval "''$(mise activate zsh)"
        if [ -d "''$HOME/.local/share/mise/shims" ]; then
          export PATH="''$HOME/.local/share/mise/shims:''$PATH"
        fi
      fi

      # Google Cloud SDK configuration
      GCLOUD_SDK_PATHS=(
        "''$HOME/Downloads/google-cloud-sdk"
        "''$HOME/google-cloud-sdk"
        "''$HOME/.google-cloud-sdk"
        "/usr/local/google-cloud-sdk"
      )
      for GCLOUD_SDK_PATH in "''${GCLOUD_SDK_PATHS[@]}"; do
        if [ -f "''$GCLOUD_SDK_PATH/path.zsh.inc" ]; then
          . "''$GCLOUD_SDK_PATH/path.zsh.inc"
          if [ -f "''$GCLOUD_SDK_PATH/completion.zsh.inc" ]; then
            . "''$GCLOUD_SDK_PATH/completion.zsh.inc"
          fi
          break
        fi
      done

      # dbt Fusion extension
      if [ -f "''$HOME/.local/bin/dbt" ]; then
        alias dbtf="''$HOME/.local/bin/dbt"
      fi

      # Antigravity
      if [ -d "''$HOME/.antigravity/antigravity/bin" ]; then
        export PATH="''$HOME/.antigravity/antigravity/bin:''$PATH"
      fi

      # Java configuration (macOS + Homebrew OpenJDK)
      if [[ "''$OSTYPE" == "darwin"* ]]; then
        HOMEBREW_PREFIX="/opt/homebrew"
        if [ ! -d "''$HOMEBREW_PREFIX" ]; then
          HOMEBREW_PREFIX="/usr/local"
        fi
        for JAVA_VERSION in "17" "21" "11"; do
          JAVA_HOME_CANDIDATE="''$HOMEBREW_PREFIX/opt/openjdk@''$JAVA_VERSION/libexec/openjdk.jdk/Contents/Home"
          if [ -d "''$JAVA_HOME_CANDIDATE" ]; then
            export JAVA_HOME="''$JAVA_HOME_CANDIDATE"
            export PATH="''$JAVA_HOME/bin:''$PATH"
            break
          fi
        done
      fi

      # Kiro terminal integration
      if command -v kiro >/dev/null 2>&1 && [[ "''$TERM_PROGRAM" == "kiro" ]]; then
        KIRO_INTEGRATION_PATH="''$(kiro --locate-shell-integration-path zsh 2>/dev/null)"
        if [ -f "''$KIRO_INTEGRATION_PATH" ]; then
          . "''$KIRO_INTEGRATION_PATH"
        fi
      fi

      # dbt Fusion extension (ensure dbt binary dir on PATH)
      if [[ ":''$PATH:" != *":''$HOME/.local/bin:"* ]]; then
        export PATH="''$HOME/.local/bin:''$PATH"
      fi
    '';
  };

  home.shellAliases = {
    # Home Managerの設定を更新するコマンドのエイリアス
    hms = "nix run --impure github:nix-community/home-manager/release-25.11 -- switch --flake .#default";

    # その他
    ll = "ls -l";

    # Git aliases（.zshrc より）
    co = "git checkout";
    br = "git branch";
    st = "git status";
    gif = "git diff";
    gifs = "git diff --staged";
    gil = "git pull";
    cm = "git commit";

    # その他の aliases
    pn = "pnpm";
  };
}
