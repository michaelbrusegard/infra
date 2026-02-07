{lib, ...}: {
  custom.vim.lsp = {
    enable = true;
    onAttach = ''
      vim.keymap.set("n", "grr", function() Snacks.picker.lsp_references() end, { buffer = bufnr, desc = "References" })
      vim.keymap.set("n", "gri", function() Snacks.picker.lsp_implementations() end, { buffer = bufnr, desc = "Implementation" })
      vim.keymap.set("n", "grt", function() Snacks.picker.lsp_type_definitions() end, { buffer = bufnr, desc = "Type Definition" })
      vim.keymap.set("n", "gO", function() Snacks.picker.lsp_symbols() end, { buffer = bufnr, desc = "Document Symbols" })
      vim.keymap.set("n", "gW", function() Snacks.picker.lsp_workspace_symbols() end, { buffer = bufnr, desc = "Workspace Symbols" })

      if client:supports_method("textDocument/inlayHint") then
        vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
      end

      if client:supports_method("textDocument/codeLens") then
        vim.lsp.codelens.refresh()
        vim.api.nvim_create_autocmd({"BufEnter", "CursorHold", "InsertLeave"}, {
          buffer = bufnr,
          callback = vim.lsp.codelens.refresh,
        })
      end

      if client:supports_method("textDocument/foldingRange") then
        vim.wo[bufnr].foldmethod = "expr"
        vim.wo[bufnr].foldexpr = "v:lua.vim.lsp.foldexpr()"
      end
    '';
  };
  programs.nvf.settings.vim.diagnostics = {
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
}
