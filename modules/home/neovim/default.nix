{inputs, ...}: {
  imports = [
    inputs.nvf.homeManagerModules.default
    ./options.nix
    ./autocmds.nix
    ./keymaps.nix
    ./colorscheme.nix
    ./util.nix
    ./editor.nix
    ./coding.nix
    ./ui.nix
    ./treesitter.nix
    ./ai.nix
    ./test.nix
    ./lsp-custom.nix
    ./lsp.nix

    ./formatting.nix
    ./linting.nix
    ./dap.nix
    ./lang/nix.nix
    # ./lang/python.nix
    # ./lang/typescript.nix
  ];
  programs.nvf.enable = true;
}
