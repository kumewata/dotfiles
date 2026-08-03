{
  config,
  pkgs,
  username,
  ...
}:

{
  programs.tmux = {
    enable = true;

    # prefix を C-t にする。
    # 既定の C-b は herdr の prefix と衝突し、C-a は shell の beginning-of-line と衝突する。
    prefix = "C-t";
  };
}
