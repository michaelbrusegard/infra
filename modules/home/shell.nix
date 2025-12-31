{ pkgs, lib, config, inputs, ... }:

let
  safeRm = pkgs.writeScriptBin "rm" ''
    #!${pkgs.zsh}/bin/zsh
    if [ $# -eq 1 ] && [[ "$1" != -* ]]; then
      exec ${pkgs.trash-cli}/bin/trash "$1"
    fi
    exec ${pkgs.coreutils}/bin/rm "$@"
  '';

  toDnxhr = pkgs.writeScriptBin "to-dnxhr" ''
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
      if ${pkgs.file}/bin/file -b --mime-type "''$path" | ${pkgs.ripgrep}/bin/rg -q "^video/"; then
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
          if ${pkgs.file}/bin/file -b --mime-type "''$file" | ${pkgs.ripgrep}/bin/rg -q "^video/"; then
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
  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";
    enableVteIntegration = true;
    autocd = true;
    enableCompletion = true;
    autosuggestion = {
      enable = true;
      highlight = "fg=${pkgs.catppuccin.mocha.overlay0}";
    };
    syntaxHighlighting.enable = true;
    history = {
      append = true;
      expireDuplicatesFirst = true;
      ignoreAllDups = true;
      saveNoDups = true;
      ignoreDups = true;
      findNoDups = true;
      ignoreSpace = true;
      extended = true;
      share = true;
      path = "$ZDOTDIR/.zsh_history";
    };
    historySubstringSearch = {
      enable = true;
      searchUpKey = "^P";
      searchDownKey = "^N";
    };
    initContent = ''
      if [[ -r "${config.xdg.cacheHome}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "${config.xdg.cacheHome}/p10k-instant-prompt-''${(%):-%n}.zsh"
      fi

      source ${inputs.self}/config/zsh/p10k.zsh
      bindkey -v
      export KEYTIMEOUT=1
      bindkey '^Y' autosuggest-accept
      bindkey '^E' autosuggest-clear
    '';
    antidote = {
      enable = true;
      useFriendlyNames = true;
      plugins = [
        "romkatv/powerlevel10k"
        "getantidote/use-omz"
        "ohmyzsh/ohmyzsh path:lib"
        "ohmyzsh/ohmyzsh path:plugins/git"
        "ohmyzsh/ohmyzsh path:plugins/docker"
        "ohmyzsh/ohmyzsh path:plugins/docker-compose"
        "ohmyzsh/ohmyzsh path:plugins/gradle"
      ];
    };
  };
  programs.fd = {
    enable = true;
    hidden = true;
    ignores = [
      ".git"
      ".DS_Store"
    ];
  };
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    options = ["--cmd cd"];
  };
  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    colors = "always";
    git = true;
    icons = "always";
    extraOptions = [
      "-a"
      "-1"
    ];
  };
  programs.bat = {
    enable = true;
    config = {
      color = "always";
      italic-text = "always";
      style = "numbers";
      pager = "delta";
      paging = "never";
      map-syntax = [
        ".ignore:.gitignore"
      ];
    };
  };
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --hidden --strip-cwd-prefix --exclude .git --exclude .DS_Store";
    fileWidgetCommand = "fd --hidden --strip-cwd-prefix --exclude .git --exclude .DS_Store";
    fileWidgetOptions = [
      "--preview 'if [ -d {} ]; then eza --tree --color=always {} | head -200; elif file --mime-type {} | grep -q \"image/\"; then chafa -f iterm -s \${FZF_PREVIEW_COLUMNS}x\${FZF_PREVIEW_LINES} {}; else bat -n --color=always --line-range :500 {}; fi'"
    ];
    historyWidgetOptions = [
      "--sort"
      "--exact"
    ];
  };
  programs.pay-respects = {
    enable = true;
    enableZshIntegration = true;
    options = [
      "--alias"
      "f"
    ];
  };
  programs.ripgrep.enable = true;
  programs.jq.enable = true;
  programs.fastfetch.enable = true;
  programs.btop.enable = true;
  programs.nix-index.enable = true;

  home.packages = with pkgs; [
    trash-cli
    libqalculate
    moor
    dust
    duf
    procs
    safeRm
    toDnxhr
  ];

  home.pointerCursor = lib.mkIf (!pkgs.stdenv.isDarwin) {
    package = pkgs.apple-cursor;
    name = "macOS";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  home.shellAliases =
    {
      rebuild =
        if pkgs.stdenv.isDarwin
        then "sudo darwin-rebuild switch --flake $HOME/Developer/dotfiles#$(hostname)"
        else "sudo nixos-rebuild switch --flake $HOME/Developer/dotfiles#$(hostname)";

      update-nix = "nix flake update nixpkgs nixpkgs-unstable nix-darwin nur home-manager sops-nix nixos-raspberrypi nixpkgs-otbr nixos-wsl lanzaboote apple-emoji-linux apple-fonts catppuccin --flake $HOME/Developer/dotfiles";
      update-desktop = "nix flake update hyprland dgop dms-cli dankMaterialShell --flake $HOME/Developer/dotfiles";
      update-apps = "nix flake update yazi wezterm affinity --flake $HOME/Developer/dotfiles";
      update-secrets = "nix flake update dotfiles-private --flake $HOME/Developer/dotfiles";
      update-homebrew = "nix flake update nix-homebrew homebrew-core homebrew-cask homebrew-extras --flake $HOME/Developer/dotfiles";

      clean = "nix-collect-garbage -d && sudo nix-collect-garbage -d && nix store optimise";
      reload = "source $HOME/.config/zsh/.zshrc";

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

      ls = "eza";
      cat = "bat";
      sed = "sd";
      htop = "btop";
      top = "btop";
      vim = "nvim";
      vi = "nvim";
      bc = "qalc";
      less = "moor";
      more = "moor";
      du = "dust";
      df = "duf";
      ps = "procs";
      lzg = "lazygit";
    }
    // lib.optionalAttrs pkgs.stdenv.isLinux {
      toggle-kanata = ''
        if systemctl is-active --quiet kanata-default.service; then
          sudo systemctl stop kanata-default.service
        else
          sudo systemctl start kanata-default.service
        fi
      '';
    }
    // lib.optionalAttrs pkgs.stdenv.isDarwin {
      toggle-kanata = ''
        if launchctl list | grep -q org.nixos.kanata; then
          sudo launchctl bootout system /Library/LaunchDaemons/org.nixos.kanata.plist
        else
          sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.kanata.plist
        fi
      '';
      restart-yabai = "launchctl kickstart -k gui/$(id -u)/org.nixos.yabai";
      groundctl = "cd $HOME/Developer/Telescope/tooling/groundctl && uv run groundctl";
    };

  home.sessionVariables = {
    PAGER = "moor";
    SOPS_AGE_KEY_FILE = config.sops.age.keyFile;
    GOOGLE_GENERATIVE_AI_API_KEY = "$( [ -f ${config.secrets.keys.googleGenerativeAiApiKeyFile} ] && ${pkgs.coreutils}/bin/cat ${config.secrets.keys.googleGenerativeAiApiKeyFile} )";
    TAURI_SIGNING_PRIVATE_KEY = "$( [ -f ${config.secrets.keys.tauriSigningPrivateKeyFile} ] && ${pkgs.coreutils}/bin/cat ${config.secrets.keys.tauriSigningPrivateKeyFile} )";
  };

  home.sessionPath =
    [
      "$HOME/.local/bin"
      "$HOME/bin"
      "$HOME/.cargo/bin"
      "$HOME/.local/state/pnpm"
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      "/opt/homebrew/bin"
    ];

  home.activation = lib.optionalAttrs pkgs.stdenv.isDarwin {
    createScreenshotsDir =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -p "$HOME/Pictures/screenshots"
      '';
  };
}
