{pkgs, lib, ...}: {
  programs.neovim.spec = {
    treesitter.grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      ninja
      rst
    ];

    lsp.servers.ty.package = pkgs.ty;

    linting.filetypes.python.ruff.package = pkgs.ruff-unstable;

    formatting.filetypes.python = {
      ruff_organize = {
        package = pkgs.ruff-unstable;
        args = ["check" "--select" "I" "--fix" "--stdin-filename" "-" "-"];
      };
      ruff_format = {
        package = pkgs.ruff-unstable;
        args = ["format" "-"];
      };
    };

    test.adapters = ["neotest-python"];

    plugins = {
      "nvim-dap-python" = {
        package = pkgs.vimPlugins.nvim-dap-python;
        setupModule = "dap-python";
        setupOpts = "${lib.getExe' pkgs.python3Packages.debugpy "debugpy-adapter"}";
        after = "nvim-dap";
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
        after = "neotest";
      };
    };
  };
}
