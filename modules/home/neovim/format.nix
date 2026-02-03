_: {
  programs.nvf.settings.vim = {
    formatter.conform-nvim = {
      enable = true;
      setupOpts = {
        default_format_opts = {
          timeout_ms = 3000;
          async = false;
          quiet = false;
          lsp_format = "fallback";
        };
        formatters_by_ft = {
          lua = ["stylua"];
          sh = ["shfmt"];
        };
        formatters = {
          injected = {options = {ignore_errors = true;};};
        };
      };
    };

    keymaps = [
      {
        key = "<leader>cF";
        mode = ["n" "x"];
        lua = true;
        action = ''
          function()
            require("conform").format({ formatters = { "injected" }, timeout_ms = 3000 })
          end
        '';
        options = {desc = "Format Injected Langs";};
      }
    ];
  };
}
