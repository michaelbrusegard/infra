{pkgs, ...}: {
  programs.nvf.settings.vim = {
    languages.python = {
      enable = true;
      treesitter.enable = true;
      lsp.enable = true;
      format = {
        enable = true;
        type = ["ruff-check" "ruff"];
      };
      dap.enable = true;
    };
    lazy.plugins."neotest-python" = {
      package = pkgs.vimPlugins.neotest-python;
      lazy = true;
    };
  };
}
