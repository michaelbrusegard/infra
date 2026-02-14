{pkgs, ...}: {
  programs.neovim.spec = {
    treesitter.grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      ninja
      rst
    ];

    lsp.servers.ty.package = pkgs.ty;

    linting.filetypes.python.ruff.package = pkgs.ruff;

    formatting.filetypes.python.ruff = {
      package = pkgs.ruff;
      args = ["format" "-"];
    };

    test.adapters = ["neotest-python"];

    plugins = {
      "nvim-dap-python" = {
        package = pkgs.vimPlugins.nvim-dap-python;
        setupModule = "dap-python";
        setupOpts = "${pkgs.python3Packages.debugpy}/bin/debugpy-adapter";
        filetype = ["python"];
        keymaps = [
          {
            key = "<leader>dPt";
            mode = ["n"];
            desc = "Debug Method";
            action = "function() require('dap-python').test_method() end";
            lua = true;
          }
          {
            key = "<leader>dPc";
            mode = ["n"];
            desc = "Debug Class";
            action = "function() require('dap-python').test_class() end";
            lua = true;
          }
        ];
      };

      "neotest-python" = {
        package = pkgs.vimPlugins.neotest-python;
      };
    };
  };
}
