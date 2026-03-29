{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  gitBin = "${pkgs.git}/bin/git";
  catBin = "${pkgs.coreutils}/bin/cat";
  printfBin = "${pkgs.coreutils}/bin/printf";
  signingKeyPath = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
  allowedSignersPath = "${config.xdg.configHome}/git/allowed_signers";
in
{
  home.file.".config/git/ignore".text =
    builtins.concatStringsSep "\n" [
      ".DS_Store"
      ".direnv/"
      ".env"
      "node_modules/"
      ".mcp.json"
      ".steering/"
      "**/.claude/settings.local.json"
    ]
    + "\n";

  home.activation.gitSshSigning = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -f "${signingKeyPath}" ]; then
      echo "[git-signing] ${signingKeyPath} not found; skipping SSH signing setup" >&2
    else
      ${gitBin} config --global gpg.format ssh
      ${gitBin} config --global user.signingKey "${signingKeyPath}"
      ${gitBin} config --global commit.gpgsign true
      ${gitBin} config --global tag.gpgsign true
      ${gitBin} config --global gpg.ssh.allowedSignersFile "${allowedSignersPath}"

      current_email="$(${gitBin} config --global --get user.email || true)"
      if [ -z "$current_email" ]; then
        echo "[git-signing] user.email is not set; skipping allowed signers file update" >&2
      else
        mkdir -p "${config.xdg.configHome}/git"
        signing_key="$(${catBin} "${signingKeyPath}")"
        ${printfBin} '%s %s\n' "$current_email" "$signing_key" > "${allowedSignersPath}"
      fi
    fi
  '';
}
