{inputs, ...}: {
  imports = [
    inputs.nvf.homeManagerModules.default
    ./options.nix
    ./autocmds.nix
    ./keymaps.nix
    ./colorscheme.nix
    ./ai.nix
    ./treesitter.nix
    ./test.nix

    ./util.nix

    ./coding.nix
    ./ui.nix
    ./editor.nix
    ./dap.nix
    ./lsp.nix
    ./formatting.nix
    ./linting.nix
    # ./lang/python.nix
    # ./lang/typescript.nix
  ];
  programs.nvf.enable = true;
}
