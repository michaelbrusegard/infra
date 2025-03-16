{ config, lib, pkgs, catppuccin, ... }:

let
  cfg = config.modules.terminal.shell;
in {
  options.modules.terminal.shell = {
    enable = lib.mkEnableOption "Shell configuration";
  };

  config = lib.mkIf cfg.enable {
    programs = {
      zsh = {
        enable = true;
        dotDir = ".config/zsh";
        enableVteIntegration = true;
        autocd = true;
        defaultKeymap = "vicmd";
        enableCompletion = true;
        autosuggestion = {
          enable = true;
          highlight = "fg=${catppuccin.flavors.mocha.overlay0}";
        };
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
        shellAliases = {
          reload = "source ~/.zshrc";
          dl = "cd ~/Downloads";
          dt = "cd ~/Desktop";
          dc = "cd ~/Documents";
          dp = "cd ~/Developer";
          ".." = "cd ..";
          "..." = "cd ../..";
          "...." = "cd ../../..";
          "....." = "cd ../../../..";
          "......" = "cd ../../../../..";
          "-" = "cd -";
          ls = "eza";
          cat = "bat";
          lzd = "lazygit";
        };
        antidote = {
          enable = true;
          useFriendlyNames = true;
          plugins = [
            "sindresorhus/pure kind:fpath"
            "getantidote/use-omz"
            "ohmyzsh/ohmyzsh path:lib"
            "ohmyzsh/ohmyzsh path:plugins/git"
            "ohmyzsh/ohmyzsh path:plugins/docker"
            "ohmyzsh/ohmyzsh path:plugins/docker-compose"
            "ohmyzsh/ohmyzsh path:plugins/gradle"
          ];
        };
      };
      catppuccin.zsh-syntax-highlighting.enable = true;
      fd = {
        enable = true;
        hidden = true;
        ignores = [
          ".git"
          ".DS_Store"
        ];
      };
      zoxide = {
        enable = true;
        enableZshIntegration = true;
        options = ["--cmd cd"];
      };
      eza = {
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
      bat = {
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
      catppuccin.bat.enable = true;
      fzf = {
        enable = true;
        enableZshIntegration = true;
        defaultCommand = "fd --hidden --strip-cwd-prefix --exclude .git --exclude .DS_Store";
        fileWidgetCommand = "fd --hidden --strip-cwd-prefix --exclude .git --exclude .DS_Store";
        fileWidgetOptions = [
          "--preview 'if [ -d {} ]; then eza --tree --color=always {} | head -200; elif file --mime-type {} | grep -q \"image/\"; then chafa -f iterm -s ${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES} {}; else bat -n --color=always --line-range :500 {}; fi'"
        ];
        historyWidgetOptions = [
          "--sort"
          "--exact"
        ];
      };
      catppuccin.fzf = {
        enable = true;
        accent = "mauve";
      };
      ripgrep.enable = true;
      thefuck = {
        enable = true;
        enableZshIntegration = true;
        enableInstantMode = true;
      };
      jq.enable = true;
      fastfetch.enable = true;
    };
  };
}
