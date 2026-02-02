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
          lua = [ "stylua" ];
          sh = [ "shfmt" ];
        };
        formatters = {
          injected = { options = { ignore_errors = true; }; };
        };
      };
    };

    maps.normal = {
      "<leader>cF" = {
        action = ''
          function()
            require("conform").format({ formatters = { "injected" }, timeout_ms = 3000 })
          end
        '';
        lua = true;
        desc = "Format Injected Langs";
        mode = [ "n" "x" ];
      };
    };
  };
}
