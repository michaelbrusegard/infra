{inputs, ...}: {
  imports = [
    inputs.nvf.homeManagerModules.default
    ./options.nix
    ./autocmds.nix
    ./keymaps.nix
    ./colorscheme.nix
    ./util.nix
    ./editor.nix
    ./ai.nix
    ./treesitter.nix
    ./test.nix

    ./coding.nix
    ./ui.nix
    ./dap.nix
    ./lsp.nix
    ./formatting.nix
    ./linting.nix
    # ./lang/python.nix
    # ./lang/typescript.nix
  ];
  programs.nvf.enable = true;
}
