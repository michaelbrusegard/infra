{ pkgs, catppuccin, ... }: {
  programs.zsh = {
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
      ignoreSpace = true;
      extended = true;
      share = true;
      saveNoDups = true;
      path = "$ZDOTDIR/.zsh_history";
    };
    historySubstringSearch = {
      enable = true;
      searchUpKey = "^P";
      searchDownKey = "^N";
    };
    antidote = {
      enable = true;
      useFriendlyNames = true;
      plugins = [
        "zsh-users/zsh-autosuggestions"
      ]
    }
  };
};
