{pkgs, ...}: {
  programs.nvf.settings.vim = {
    languages.python = {
      enable = true;
      treesitter.enable = true;
      lsp = {
        enable = true;
        servers = ["basedpyright" "ruff"];
      };
      dap.enable = true;
    };
    lazy.plugins."neotest-python" = {
      package = pkgs.vimPlugins.neotest-python;
      setupModule = "neotest-python";
      setupOpts = {};
      lazy = true;
    };
  };
}
