_: {
  imports = [
    ./spec
    ./dependencies.nix
    ./options.nix
    ./autocmds.nix
    ./keymaps.nix
    ./colorscheme.nix
    ./ui.nix
    ./util.nix
    ./coding.nix
    ./editor.nix
    ./treesitter.nix
    ./lsp.nix
    ./opencode.nix
    ./formatting.nix
    ./test.nix
    ./lang/nix.nix
    ./lang/python.nix
    ./lang/typescript.nix

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
