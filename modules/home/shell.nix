{
  pkgs,
  lib,
  config,
  inputs,
  homePersistenceRoot ? null,
  ...
}: {
  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";
    enableVteIntegration = true;
    autocd = true;
    enableCompletion = true;
    autosuggestion = {
      enable = true;
      highlight = "fg=#6c7086";
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

      source ${inputs.self}/config/shell/p10k.zsh
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

  home =
    {
      shellAliases = {
        dl = "cd $HOME/Downloads";
        dt = "cd $HOME/Desktop";
        dc = "cd $HOME/Documents";
        dp = "cd $HOME/Projects";

        ".." = "cd ..";
        "..." = "cd ../..";
        "...." = "cd ../../..";
        "....." = "cd ../../../..";
        "......" = "cd ../../../../..";
        "-" = "cd -";

        vim = "nvim";
        vi = "nvim";
      };

      sessionVariables = {
        SOPS_AGE_KEY_FILE = config.sops.age.keyFile;
      };

      sessionPath =
        [
          "$HOME/.local/bin"
          "$HOME/bin"
          "$HOME/.cargo/bin"
          "$HOME/.local/state/pnpm"
        ]
        ++ lib.optionals pkgs.stdenv.isDarwin [
          "/opt/homebrew/bin"
        ];

      activation = lib.optionalAttrs pkgs.stdenv.isDarwin {
        createScreenshotsDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
          $DRY_RUN_CMD mkdir -p "$HOME/Pictures/screenshots"
        '';
      };
    }
    // lib.optionalAttrs (homePersistenceRoot != null) {
      persistence.${homePersistenceRoot} = {
        directories = [
          ".cache/antidote"
          ".local/state/pnpm"
        ];
        files = [
          ".config/zsh/.zsh_history"
        ];
      };
    };
}
