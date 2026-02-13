{
  pkgs,
  lib,
  ...
}: {
  programs.neovim.spec = {
    treesitter.grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      json
      json5
    ];

    lsp.servers.jsonls = {
      package = pkgs.vscode-langservers-extracted;
      config.on_new_config = lib.generators.mkLuaInline ''
        function(new_config)
          new_config.settings.json.schemas = new_config.settings.json.schemas or {}
          vim.list_extend(new_config.settings.json.schemas, require("schemastore").json.schemas())
        end
      '';
      settings = {
        json = {
          format = {enable = true;};
          validate = {enable = true;};
        };
      };
    };

    formatting.filetypes = {
      json.oxfmt = {
        package = pkgs.oxfmt;
        args = ["--stdin-filepath" "$FILENAME"];
      };
      json5.oxfmt = {
        package = pkgs.oxfmt;
        args = ["--stdin-filepath" "$FILENAME"];
      };
    };
  };
}
