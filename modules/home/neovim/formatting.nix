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
    ];
    filetypes = {
      sh = {
        shfmt = {
          package = pkgs.shfmt;
        };
      };
      typescript = {
        prettier = {
          package = pkgs.nodePackages.prettier;
          requiredFiles = [".prettierrc" ".prettierrc.json" ".prettierrc.js"];
        };
        biome = {
          args = ["check" "--apply" "--stdin-file-path" "$FILENAME"];
          package = pkgs.biome;
          requiredFiles = ["biome.json"];
        };
        oxfmt = {
          package = pkgs.oxlint;
        };
      };
      lua = {
        stylua = {
          package = pkgs.stylua;
        };
      };
      python = {
        ruff = {
          args = ["format" "--stdin-filename" "$FILENAME" "-"];
          package = pkgs.ruff;
        };
      };
    };
  };
}
