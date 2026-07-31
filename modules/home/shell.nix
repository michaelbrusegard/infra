{
  pkgs,
  lib,
  config,
  inputs,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: {
  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";
    enableVteIntegration = true;
    autocd = true;
    enableCompletion = false;
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
      path = "${config.xdg.configHome}/zsh/.zsh_history";
    };
    historySubstringSearch = {
      enable = true;
      searchUpKey = "^P";
      searchDownKey = "^N";
    };
    initContent = lib.mkMerge [
      (lib.mkOrder 500 ''
        if [[ -r "${config.xdg.cacheHome}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "${config.xdg.cacheHome}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      '')
      (lib.mkOrder 1000 ''
        source ${inputs.self}/config/shell/p10k.zsh
        bindkey -v
        export KEYTIMEOUT=1
        bindkey '^Y' autosuggest-accept
        bindkey '^E' autosuggest-clear

        typeset -gA __direnv_zsh_completions

        _direnv_load_zsh_completions() {
          emulate -L zsh

          (( $+functions[compdef] )) || return 0

          local -A desired_completions
          local spec command completion_file loaded_command

          for spec in ''${(z)DIRENV_ZSH_COMPLETIONS}; do
            command="''${spec%%=*}"
            completion_file="''${spec#*=}"

            if [[ -z "$command" || "$command" == "$spec" || -z "$completion_file" || ! -r "$completion_file" ]]; then
              continue
            fi

            desired_completions[$command]="$completion_file"

            if [[ "''${__direnv_zsh_completions[$command]-}" != "$completion_file" ]]; then
              compdef -d "$command" 2>/dev/null || true
              source "$completion_file"
              __direnv_zsh_completions[$command]="$completion_file"
            fi
          done

          for loaded_command in ''${(k)__direnv_zsh_completions}; do
            if [[ -z "''${desired_completions[$loaded_command]-}" ]]; then
              compdef -d "$loaded_command" 2>/dev/null || true
              unset "__direnv_zsh_completions[$loaded_command]"
            fi
          done
        }

        autoload -Uz add-zsh-hook
        add-zsh-hook precmd _direnv_load_zsh_completions
        _direnv_load_zsh_completions
      '')
    ];
    antidote = {
      enable = true;
      useFriendlyNames = true;
      plugins = [
        "getantidote/use-omz"
        "romkatv/powerlevel10k path:powerlevel10k.zsh-theme"
        "ohmyzsh/ohmyzsh path:plugins/git"
        "ohmyzsh/ohmyzsh path:plugins/docker"
        "ohmyzsh/ohmyzsh path:plugins/docker-compose"
        "ohmyzsh/ohmyzsh path:plugins/gradle"
      ];
    };
  };

  home =
    {
      shellAliases =
        {
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
        }
        // lib.optionalAttrs (pkgs.stdenv.isLinux && !isWsl) {
          pbcopy = "wl-copy";
          pbpaste = "wl-paste";
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
          ".cache/gitstatus"
          ".cache/p10k-${config.home.username}"
        ];
        files = [
          ".config/zsh/.zsh_history"
        ];
      };
    };
}
