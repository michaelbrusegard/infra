{
  pkgs,
  lib,
  ...
}: {
  programs.neovim.spec = {
    lsp.servers.tailwindcss = {
      package = pkgs.tailwindcss-language-server;
      settings = {
        tailwindCSS = {
          includeLanguages = {
            elixir = "html-eex";
            eelixir = "html-eex";
            heex = "html-eex";
          };
        };
      };
      config = lib.generators.mkLuaInline ''
        {
          on_new_config = function(new_config)
            if not new_config.filetypes then
              return
            end
            local exclude = { "markdown" }
            new_config.filetypes = vim.tbl_filter(function(ft)
              return not vim.tbl_contains(exclude, ft)
            end, new_config.filetypes)
          end
        }
      '';
    };
  };
}
