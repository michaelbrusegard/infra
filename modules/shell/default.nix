{ config, lib, pkgs, colors, ... }:

let
  cfg = config.modules.shell;
in {
  options.modules.shell.enable = lib.mkEnableOption "Shell configuration";

  config = lib.mkIf cfg.enable {
    programs = {
      zsh = {
        enable = true;
        dotDir = ".config/zsh";
        enableVteIntegration = true;
        autocd = true;
        # defaultKeymap = "vicmd";
        enableCompletion = true;
        autosuggestion = {
          enable = true;
          highlight = "fg=${colors.mocha.overlay0}";
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
        initExtraFirst = ''
        '';
        initExtra = ''
          source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
          bindkey '^Y' autosuggest-accept
          bindkey '^E' autosuggest-clear
        '';
        antidote = {
          enable = true;
          useFriendlyNames = true;
          plugins = [
            "getantidote/use-omz"
            "ohmyzsh/ohmyzsh path:lib"
            "ohmyzsh/ohmyzsh path:plugins/git"
            "ohmyzsh/ohmyzsh path:plugins/docker"
            "ohmyzsh/ohmyzsh path:plugins/docker-compose"
            "ohmyzsh/ohmyzsh path:plugins/gradle"
          ];
        };
      };
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
      fzf = {
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
      ripgrep.enable = true;
      thefuck = {
        enable = true;
        enableZshIntegration = true;
        enableInstantMode = true;
      };
      jq.enable = true;
      fastfetch.enable = true;
    };
    home.packages = with pkgs; [
      zsh-powerlevel10k
    ];
    catppuccin = {
      zsh-syntax-highlighting.enable = true;
      bat.enable = true;
      fzf = {
        enable = true;
        accent = "blue";
      };
    };
  };
}
