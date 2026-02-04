{lib, ...}: {
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
        goToDeclaration = "gD";
        hover = "K";
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

    keymaps = [
      {
        key = "gd";
        mode = "n";
        lua = true;
        action = "function() require('snacks').picker.lsp_definitions() end";
        options = {desc = "Goto Definition";};
      }
      {
        key = "grr";
        mode = "n";
        lua = true;
        action = "function() require('snacks').picker.lsp_references() end";
        options = {desc = "References";};
      }
      {
        key = "gri";
        mode = "n";
        lua = true;
        action = "function() require('snacks').picker.lsp_implementations() end";
        options = {desc = "Goto Implementation";};
      }
      {
        key = "grt";
        mode = "n";
        lua = true;
        action = "function() require('snacks').picker.lsp_type_definitions() end";
        options = {desc = "Goto Type Definition";};
      }
      {
        key = "gO";
        mode = "n";
        lua = true;
        action = "function() require('snacks').picker.lsp_symbols() end";
        options = {desc = "Document Symbols";};
      }
      {
        key = "gK";
        mode = "n";
        lua = true;
        action = "function() vim.lsp.buf.signature_help() end";
        options = {desc = "Signature Help";};
      }
      {
        key = "<leader>ss";
        mode = "n";
        lua = true;
        action = "function() require('snacks').picker.lsp_symbols() end";
        options = {desc = "LSP Symbols";};
      }
      {
        key = "<leader>sS";
        mode = "n";
        lua = true;
        action = "function() require('snacks').picker.lsp_workspace_symbols() end";
        options = {desc = "LSP Workspace Symbols";};
      }
      {
        key = "gai";
        mode = "n";
        lua = true;
        action = "function() require('snacks').picker.lsp_incoming_calls() end";
        options = {desc = "Calls Incoming";};
      }
      {
        key = "gao";
        mode = "n";
        lua = true;
        action = "function() require('snacks').picker.lsp_outgoing_calls() end";
        options = {desc = "Calls Outgoing";};
      }
      {
        key = "<leader>cc";
        mode = ["n" "x"];
        lua = true;
        action = "function() vim.lsp.codelens.run() end";
        options = {desc = "Run Codelens";};
      }
      {
        key = "<leader>cC";
        mode = "n";
        lua = true;
        action = "function() vim.lsp.codelens.refresh() end";
        options = {desc = "Refresh & Display Codelens";};
      }
      {
        key = "<leader>cR";
        mode = "n";
        lua = true;
        action = "function() require('snacks').rename.rename_file() end";
        options = {desc = "Rename File";};
      }
      {
        key = "]]";
        mode = "n";
        lua = true;
        action = "function() require('snacks').words.jump(vim.v.count1) end";
        options = {desc = "Next Reference";};
      }
      {
        key = "[[";
        mode = "n";
        lua = true;
        action = "function() require('snacks').words.jump(-vim.v.count1) end";
        options = {desc = "Prev Reference";};
      }
      {
        key = "<c-s>";
        mode = "i";
        lua = true;
        action = "function() vim.lsp.buf.signature_help() end";
        options = {desc = "Signature Help";};
      }
    ];
  };
}
