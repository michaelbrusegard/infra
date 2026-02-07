{lib, ...}: {
  programs.nvf.settings.vim = {
    lsp = {
      enable = true;
      formatOnSave = true;
      inlayHints.enable = true;
      mappings = {
        renameSymbol = "grn";
        codeAction = "gra";
        goToDeclaration = "gD";
        hover = "K";
      };
    };

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

    lsp.servers = {
      "lua_ls" = {
        settings = {
          Lua = {
            workspace = {checkThirdParty = false;};
            codeLens = {enable = true;};
            completion = {callSnippet = "Replace";};
            doc = {privateName = ["^_"];};
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

    keymaps = [
      {
        key = "gd";
        mode = "n";
        desc = "Goto Definition";
        action = "function() require('snacks').picker.lsp_definitions() end";
        lua = true;
      }
      {
        key = "grr";
        mode = "n";
        desc = "References";
        action = "function() require('snacks').picker.lsp_references() end";
        lua = true;
      }
      {
        key = "gri";
        mode = "n";
        desc = "Goto Implementation";
        action = "function() require('snacks').picker.lsp_implementations() end";
        lua = true;
      }
      {
        key = "grt";
        mode = "n";
        desc = "Goto Type Definition";
        action = "function() require('snacks').picker.lsp_type_definitions() end";
        lua = true;
      }
      {
        key = "gO";
        mode = "n";
        desc = "Document Symbols";
        action = "function() require('snacks').picker.lsp_symbols() end";
        lua = true;
      }
      {
        key = "gK";
        mode = "n";
        desc = "Signature Help";
        action = "function() vim.lsp.buf.signature_help() end";
        lua = true;
      }
      {
        key = "<leader>ss";
        mode = "n";
        desc = "LSP Symbols";
        action = "function() require('snacks').picker.lsp_symbols() end";
        lua = true;
      }
      {
        key = "<leader>sS";
        mode = "n";
        desc = "LSP Workspace Symbols";
        action = "function() require('snacks').picker.lsp_workspace_symbols() end";
        lua = true;
      }
      {
        key = "gai";
        mode = "n";
        desc = "Calls Incoming";
        action = "function() require('snacks').picker.lsp_incoming_calls() end";
        lua = true;
      }
      {
        key = "gao";
        mode = "n";
        desc = "Calls Outgoing";
        action = "function() require('snacks').picker.lsp_outgoing_calls() end";
        lua = true;
      }
      {
        key = "<leader>cc";
        mode = ["n" "x"];
        desc = "Run Codelens";
        action = "function() vim.lsp.codelens.run() end";
        lua = true;
      }
      {
        key = "<leader>cC";
        mode = "n";
        desc = "Refresh & Display Codelens";
        action = "function() vim.lsp.codelens.refresh() end";
        lua = true;
      }
      {
        key = "<leader>cR";
        mode = "n";
        desc = "Rename File";
        action = "function() require('snacks').rename.rename_file() end";
        lua = true;
      }
      {
        key = "]]";
        mode = "n";
        desc = "Next Reference";
        action = "function() require('snacks').words.jump(vim.v.count1) end";
        lua = true;
      }
      {
        key = "[[";
        mode = "n";
        desc = "Prev Reference";
        action = "function() require('snacks').words.jump(-vim.v.count1) end";
        lua = true;
      }
      {
        key = "<c-s>";
        mode = "i";
        desc = "Signature Help";
        action = "function() vim.lsp.buf.signature_help() end";
        lua = true;
      }
    ];
  };
}
