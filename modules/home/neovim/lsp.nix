{
  pkgs,
  lib,
  ...
}: {
  programs.neovim.spec = {
    lsp.onAttach = ''
      vim.keymap.set("n", "<leader>cli", "<cmd>LspInfo<cr>", { buffer = bufnr, desc = "Lsp Info" })

      -- Enhanced Neovim defaults (with which-key descriptions)
      vim.keymap.set("n", "grn", require("live-rename").rename, { buffer = bufnr, desc = "Rename" })
      vim.keymap.set("n", "grr", vim.lsp.buf.references, { buffer = bufnr, desc = "References" })
      vim.keymap.set("n", "gri", vim.lsp.buf.implementation, { buffer = bufnr, desc = "Goto Implementation" })
      vim.keymap.set("n", "grt", vim.lsp.buf.type_definition, { buffer = bufnr, desc = "Goto Type Definition" })
      vim.keymap.set("n", "gO", vim.lsp.buf.document_symbol, { buffer = bufnr, desc = "Document Symbols" })
      vim.keymap.set("n", "gW", function() require("snacks").picker.lsp_workspace_symbols() end, { buffer = bufnr, desc = "Workspace Symbols" })
      vim.keymap.set({"n", "v"}, "gra", vim.lsp.buf.code_action, { buffer = bufnr, desc = "Code Action" })
      vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = bufnr, desc = "Hover" })

      -- LazyVim additions (no Neovim default)
      vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = bufnr, desc = "Goto Definition" })
      vim.keymap.set("n", "gD", vim.lsp.buf.declaration, { buffer = bufnr, desc = "Goto Declaration" })
      vim.keymap.set("n", "gK", vim.lsp.buf.signature_help, { buffer = bufnr, desc = "Signature Help" })
      vim.keymap.set("n", "[d", function() vim.diagnostic.jump({ count = -1 }) end, { buffer = bufnr, desc = "Prev Diagnostic" })
      vim.keymap.set("n", "]d", function() vim.diagnostic.jump({ count = 1 }) end, { buffer = bufnr, desc = "Next Diagnostic" })

      if client:supports_method("textDocument/inlayHint") then
        if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == "" then
          vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
        end
      end

      if client:supports_method("textDocument/codeLens") then
        vim.lsp.codelens.refresh()
        vim.api.nvim_create_autocmd({"BufEnter", "CursorHold", "InsertLeave"}, {
          buffer = bufnr,
          callback = vim.lsp.codelens.refresh,
        })
        vim.keymap.set({ "n", "v" }, "<leader>cc", vim.lsp.codelens.run, { buffer = bufnr, desc = "Run Codelens" })
        vim.keymap.set("n", "<leader>cC", vim.lsp.codelens.refresh, { buffer = bufnr, desc = "Refresh & Display Codelens" })
      end

      if client:supports_method("textDocument/foldingRange") then
        vim.wo[bufnr].foldmethod = "expr"
        vim.wo[bufnr].foldexpr = "v:lua.vim.lsp.foldexpr()"
      end
    '';
    diagnostics = {
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
    plugins = {
      "live-rename" = {
        package = pkgs.vimPlugins.live-rename-nvim;
        event = ["LspAttach"];
        setupModule = "live-rename";
      };
    };
  };
}
