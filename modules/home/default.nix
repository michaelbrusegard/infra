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
    convert_file() {
      local input_file="''$1"
      local dir="''$(${pkgs.coreutils}/bin/dirname "''$input_file")"
      local base="''$(${pkgs.coreutils}/bin/basename "''${input_file%.*}")"
      local output_file="''$dir/''$base"_dnxhr.mov
      if [ -f "''$output_file" ]; then
        echo "Skipping: '''$input_file' (output already exists)"
        return
      fi

      echo "Converting: '''$input_file'"
      echo "Output:     '''$output_file'"
      if ${pkgs.ffmpeg}/bin/ffmpeg -hide_banner -loglevel error -stats -nostdin -i "''$input_file" -c:v dnxhd -profile:v dnxhr_hq -c:a pcm_s16le -pix_fmt yuv422p "''$output_file"; then
        echo "✓ Conversion successful: ''$input_file"
      else
        echo "✗ Conversion failed: ''$input_file"
        return 1
      fi
    }

    process_path() {
      local path="''$1"
      if [ -f "''$path" ]; then
      if ${pkgs.file}/bin/file -b --mime-type "''$path" | ${pkgs.gnugrep}/bin/grep -q "^video/"; then
        if [[ "''$path" == *"_dnxhr"* ]]; then
          echo "Skipping: '''$path' (already in DNxHR format)"
        else
          convert_file "''$path"
        fi
        else
          echo "Skipping: '''$path' (not a video file)"
        fi
      elif [ -d "''$path" ]; then
        echo "Processing directory: '''$path'"
        local count=0
        local failed=0
        while IFS= read -r -d ''$'\0' file; do
          if ${pkgs.file}/bin/file -b --mime-type "''$file" | ${pkgs.gnugrep}/bin/grep -q "^video/"; then
            count=''$((count + 1))
            convert_file "''$file" || failed=''$((failed + 1))
          fi
        done < <(${pkgs.findutils}/bin/find "''$path" -type f -print0)
        echo "Directory processing complete:"
        echo "- Total videos processed: ''$count"
        echo "- Successful: ''$((count - failed))"
        echo "- Failed: ''$failed"
      else
        echo "Error: '''$path' is not a valid file or directory"
        return 1
      fi
    }

    if [ -z "''$1" ]; then
      echo "Usage: ''$(basename ''$0) <input_path>"
      echo "Converts video(s) to DNxHR HQ MOV with PCM audio for DaVinci Resolve."
      echo ""
      echo "Input can be either:"
      echo "  - A single video file"
      echo "  - A directory (will process all video files recursively)"
      exit 1
    fi

    process_path "''$1"
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
        "darwin-rebuild switch --flake $HOME/Developer/dotfiles#${hostName}"
      else
        "sudo nixos-rebuild switch --flake $HOME/Developer/dotfiles#${hostName}";
      update = "nix flake update --flake $HOME/Developer/dotfiles";
      update-secrets = "nix flake update dotfiles-private --flake $HOME/Developer/dotfiles";
      clean = "nix-collect-garbage -d && sudo nix-collect-garbage -d && nix store optimise";
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
      f = "fuck";
      ls = "eza";
      lzg = "lazygit";
      vi = "nvim";
      vim = "nvim";
    };
    sessionVariables = {
      SOPS_AGE_KEY_FILE = config.sops.age.keyFile;
      GEMINI_API_KEY = config.secrets.apiKeys.gemini;
    };
    sessionPath = [
      "$HOME/.local/bin"
      "$HOME/bin"
    ];
  };
}
