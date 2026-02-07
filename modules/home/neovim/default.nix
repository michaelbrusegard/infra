{inputs, ...}: {
  imports = [
    inputs.nvf.homeManagerModules.default
    ./options.nix
    ./autocmds.nix
    ./keymaps.nix
    ./ai.nix

    ./coding.nix
    ./dap.nix
    ./colorscheme.nix
    ./editor.nix
    ./formatting.nix
    ./linting.nix
    ./lsp.nix
    ./test.nix
    ./treesitter.nix
    ./ui.nix
    ./util.nix
    # ./lang/python.nix
    # ./lang/typescript.nix
  ];
  programs.nvf.enable = true;
}
