{ lib, config, pkgs, hostName, isDarwin, ... }:
let
  dev = pkgs.writeScriptBin "dev" ''
    #!${pkgs.zsh}/bin/zsh
    FLAKE_DIR="$HOME/Developer/dotfiles"
    if [ $# -eq 0 ]; then
      echo "Usage: dev <shell-name>"
      exit 1
    fi

    ${pkgs.nix}/bin/nix develop "$FLAKE_DIR#$1"
  '';
  to_dnxhr = pkgs.writeScriptBin "to-dnxhr" ''
    #!${pkgs.zsh}/bin/zsh
    if [ -z "''$1" ]; then
      echo "Usage: ''$(basename ''$0) <input_video_file>"
      echo "Converts video to DNxHR HQ MOV with PCM audio for DaVinci Resolve Free."
      exit 1
    fi

    input_file="''$1"
    output_file="''$(dirname "''$input_file")/''$(basename "''${input_file%.*}")_dnxhr.mov"

    echo "Input:   ' ''$input_file'"
    echo "Output:  ' ''$output_file'"
    echo "Starting conversion (DNxHR HQ / PCM 16-bit)..."

    ${pkgs.ffmpeg}/bin/ffmpeg -i "''$input_file" -c:v dnxhd -profile:v dnxhr_hq -c:a pcm_s16le -pix_fmt yuv422p "''$output_file"

    if [ ''$? -eq 0 ]; then
        echo "Conversion finished successfully."
    else
        echo "Conversion failed."
        exit 1
    fi
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
      to_dnxhr
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
