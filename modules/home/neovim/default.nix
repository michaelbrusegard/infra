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
    ./linting.nix
    ./formatting.nix
    ./ai.nix
    ./lang/nix.nix
    ./lang/python.nix
    ./lang/typescript.nix
    ./lang/rust.nix
    ./lang/json.nix
    ./lang/toml.nix
    ./lang/yaml.nix
    ./lang/markdown.nix
    ./lang/web.nix
    ./lang/git.nix

    # ./test.nix
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
