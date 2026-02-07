{lib, ...}: {
  programs.nvf.settings.vim = {
    diagnostics = {
      enable = true;
      config = {
        virtual_text = lib.generators.mkLuaInline ''
          {
            source = "if_many",
            prefix = "●",
          }
        '';
        float = lib.generators.mkLuaInline ''
          {
            source = "always",
          }
        '';
        signs.text = lib.generators.mkLuaInline ''
          {
            [vim.diagnostic.severity.ERROR] = " ",
            [vim.diagnostic.severity.WARN]  = " ",
            [vim.diagnostic.severity.HINT]  = " ",
            [vim.diagnostic.severity.INFO]  = " ",
          }
        '';
        underline = true;
        update_in_insert = false;
        severity_sort = true;
      };
    };

    luaConfigRC.lsp-setup = ''
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if client and client.supports_method("textDocument/foldingRange") then
            vim.wo.foldmethod = "expr"
            vim.wo.foldexpr = "v:lua.vim.lsp.foldexpr()"
          end
        end,
      })
    '';
  };
}
