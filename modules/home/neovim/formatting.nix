{lib, ...}: {
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
          javascript = ["oxfmt" "biome" "prettier"];
          javascriptreact = ["oxfmt" "biome" "prettier"];
          typescript = ["oxfmt" "biome" "prettier"];
          typescriptreact = ["oxfmt" "biome" "prettier"];
          vue = ["oxfmt" "biome" "prettier"];
          css = ["oxfmt" "biome" "prettier"];
          scss = ["oxfmt" "biome" "prettier"];
          less = ["oxfmt" "biome" "prettier"];
          html = ["prettier"];
          json = ["oxfmt" "biome" "prettier"];
          jsonc = ["oxfmt" "biome" "prettier"];
          yaml = ["prettier"];
          markdown = ["prettier"];
          "markdown.mdx" = ["prettier"];
          graphql = ["oxfmt" "biome" "prettier"];
          handlebars = ["prettier"];
          astro = ["oxfmt" "biome"];
          svelte = ["oxfmt" "biome"];
        };
        formatters = {
          injected = {options = {ignore_errors = true;};};
          oxfmt = {
            require_cwd = true;
          };
          biome = {
            require_cwd = true;
          };
          prettier = {
            condition = lib.generators.mkLuaInline ''
              function(ctx)
                local function has_config(path)
                  vim.fn.system({ "prettier", "--find-config-path", path })
                  return vim.v.shell_error == 0
                end

                local function has_parser(path, bufnr)
                  local ft = vim.bo[bufnr].filetype
                  local supported = {
                    "css", "graphql", "handlebars", "html", "javascript",
                    "javascriptreact", "json", "jsonc", "less", "markdown",
                    "markdown.mdx", "scss", "typescript", "typescriptreact",
                    "vue", "yaml"
                  }
                  if vim.tbl_contains(supported, ft) then return true end
                  local ret = vim.fn.system({ "prettier", "--file-info", path })
                  local ok, parser = pcall(function()
                    return vim.fn.json_decode(ret).inferredParser
                  end)
                  return ok and parser and parser ~= vim.NIL
                end

                return has_parser(ctx.filename, ctx.buf) and has_config(ctx.filename)
              end
            '';
          };
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
