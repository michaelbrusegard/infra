_: {
  imports = [
    ./spec
    ./options.nix
    ./autocmds.nix
    ./keymaps.nix
    ./colorscheme.nix
    ./ui.nix
    ./util.nix
    ./coding.nix
    ./editor.nix
    ./treesitter.nix
    ./ai.nix


    # ./test.nix
    # ./lsp.nix
    # ./formatting.nix
    # ./linting.nix
    # ./dap.nix
  ];

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
  };
}
