{ lib, config, pkgs, hostName, isDarwin, ... }:
let
  dev = pkgs.writeScriptBin "dev" ''
    #!${pkgs.zsh}/bin/zsh
    FLAKE_DIR="$HOME/Developer/dotfiles"

    list_shells() {
      echo "Available dev shells:"
      ${pkgs.nix}/bin/nix flake show --json "$FLAKE_DIR" | \
        ${pkgs.jq}/bin/jq -r '.devShells."''${system}"|keys[]' | \
        while read -r shell; do
          echo "  - $shell"
        done
    }

    if [ $# -eq 0 ]; then
      echo "Usage: dev <shell-name>"
      echo ""
      list_shells
      exit 1
    fi

    ${pkgs.nix}/bin/nix develop "$FLAKE_DIR#$1"
  '';
in
{
  home = {
    stateVersion = "25.05";
    pointerCursor = lib.mkIf (config.modules.gui.enable && !isDarwin) {
      package = pkgs.apple-cursor;
      name = "macOS";
      size = 24;
      gtk.enable = true;
      x11.enable = true;
    };
    shell.enableZshIntegration = true;
    packages = [
      dev
    ];
    shellAliases = {
      rebuild = if isDarwin then
        "sudo ${pkgs.darwin.darwin-rebuild}/bin/darwin-rebuild switch --flake $HOME/Developer/dotfiles#${hostName}"
      else
        "sudo ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake $HOME/Developer/dotfiles#${hostName}";
      update = "${pkgs.nix}/bin/nix flake update --flake $HOME/Developer/dotfiles";
      update-secrets = "${pkgs.nix}/bin/nix flake update dotfiles-private --flake $HOME/Developer/dotfiles";
      cleanup = "${pkgs.nix}/bin/nix-collect-garbage -d && ${pkgs.nix}/bin/nix store optimise";
      reload = "source $HOME/.config/zsh/.zshrc";
      c = "clear";
      dl = "cd $HOME/Downloads";
      dt = "cd $HOME/Desktop";
      dc = "cd $HOME/Documents";
      dp = "cd $HOME/Developer";
      ".." = "cd ..";
      "..." = "cd ../..";
      "...." = "cd ../../..";
      "....." = "cd ../../../..";
      "......" = "cd ../../../../..";
      "-" = "cd -";
      f = "${pkgs.thefuck}/bin/fuck";
      ls = "${pkgs.eza}/bin/eza";
      cat = "${pkgs.bat}/bin/bat";
      lzd = "${pkgs.lazygit}/bin/lazygit";
    };
    sessionPath = [
      "$HOME/.local/bin"
      "$HOME/bin"
    ];
  };
}
