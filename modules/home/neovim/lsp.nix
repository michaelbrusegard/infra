{ lib, ... }: {
  programs.nvf.settings.vim = {
    lsp = {
      enable = true;
      formatOnSave = true;
      inlayHints.enable = true;
      lspkind.enable = true;
      lspkind.setupOpts.mode = "symbol_text";
      mappings = {
        renameSymbol = "grn";
        codeAction = "gra";
        listReferences = "grr";
        listImplementations = "gri";
        goToType = "grt";
        listDocumentSymbols = "gO";
        signatureHelp = "gK";
        hover = "K";
        goToDefinition = "gd";
        goToDeclaration = "gD";
      };
    };

    diagnostics = {
      enable = true;
      config = {
        underline = true;
        update_in_insert = false;
        severity_sort = true;
        virtual_text = {
          spacing = 4;
          source = "if_many";
          prefix = "●";
        };
        signs.text = lib.generators.mkLuaInline ''
          {
            [vim.diagnostic.severity.ERROR] = " ",
            [vim.diagnostic.severity.WARN]  = " ",
            [vim.diagnostic.severity.HINT]  = " ",
            [vim.diagnostic.severity.INFO]  = " ",
          }
        '';
      };
    };

    lsp.servers = {
      "lua_ls" = {
        settings = {
          Lua = {
            workspace = { checkThirdParty = false; };
            codeLens = { enable = true; };
            completion = { callSnippet = "Replace"; };
            doc = { privateName = [ "^_" ]; };
            hint = {
              enable = true;
              setType = false;
              paramType = true;
              paramName = "Disable";
              semicolon = "Disable";
              arrayIndex = "Disable";
            };
          };
        };
      };
    };

    luaConfigRC.lsp-setup = ''
      -- Enable folds if supported
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

    maps.normal = {
      "<leader>cc" = { action = "function() vim.lsp.codelens.run() end"; lua = true; desc = "Run Codelens"; mode = ["n" "x"]; };
      "<leader>cC" = { action = "function() vim.lsp.codelens.refresh() end"; lua = true; desc = "Refresh & Display Codelens"; };
      "<leader>cR" = { action = "function() require('snacks').rename.rename_file() end"; lua = true; desc = "Rename File"; };
      "]]" = { action = "function() require('snacks').words.jump(vim.v.count1) end"; lua = true; desc = "Next Reference"; };
      "[[" = { action = "function() require('snacks').words.jump(-vim.v.count1) end"; lua = true; desc = "Prev Reference"; };
    };
    maps.insert = {
      "<c-k>" = { action = "function() vim.lsp.buf.signature_help() end"; lua = true; desc = "Signature Help"; };
    };
  };
}
