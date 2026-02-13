{
  pkgs,
  lib,
  ...
}: {
  programs.neovim.spec = {
    treesitter.grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      yaml
    ];

    lsp.servers.yamlls = {
      package = pkgs.yaml-language-server;
      config.before_init = lib.generators.mkLuaInline ''
        function(_, new_config)
          new_config.settings.yaml.schemas = vim.tbl_deep_extend(
            "force",
            new_config.settings.yaml.schemas or {},
            require("schemastore").yaml.schemas()
          )
        end
      '';
      settings = {
        redhat = {telemetry = {enabled = false;};};
        yaml = {
          keyOrdering = false;
          format = {enable = true;};
          validate = true;
          schemaStore = {
            enable = false;
            url = "";
          };
        };
      };
    };

    formatting.filetypes = {
      yaml.oxfmt = {
        package = pkgs.oxfmt;
        args = ["--stdin-filepath" "$FILENAME"];
      };
    };
  };
}
