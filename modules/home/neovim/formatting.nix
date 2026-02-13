{pkgs, ...}: {
  programs.neovim.spec.formatting = {
    keymaps = [
      {
        key = "<leader>cF";
        action = ''function() require("conform").format({ formatters = { "injected" }, timeout_ms = 3000 }) end'';
        mode = ["n" "x"];
        desc = "Format Injected Langs";
        lua = true;
      }
      {
        key = "<leader>cf";
        action = ''function() require("conform").format({ lsp_fallback = true }) end'';
        mode = ["n" "x"];
        desc = "Format Buffer";
        lua = true;
      }
      {
        key = "<leader>cfi";
        action = "<cmd>ConformInfo<cr>";
        desc = "Conform Info";
      }
    ];
    filetypes = {
      sh = {
        shfmt = {
          package = pkgs.shfmt;
        };
      };
    };
  };
}
