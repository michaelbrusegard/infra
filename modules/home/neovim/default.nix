_: {
  imports = [
    ./spec
    ./dependencies.nix
    ./spell.nix
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
    ./dap.nix
    ./test.nix
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
    ./lang/docker.nix
    ./lang/tailwind.nix
    ./lang/lua.nix
    ./lang/c.nix
  ];

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
  };
}
