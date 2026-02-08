{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types mkIf;
  cfg = config.programs.neovim.spec.treesitter;
in
{
  options.programs.neovim.spec.treesitter = {
    enable = mkOption {
      type = types.bool;
      default = true;
    };
    grammars = mkOption {
      type = types.listOf types.package;
      default = [];
    };
    setupOpts = mkOption {
      type = types.attrs;
      default = {};
    };
  };

  config = mkIf cfg.enable {
    programs.neovim.spec.plugins.nvim-treesitter = {
      package = pkgs.vimPlugins.nvim-treesitter.withPlugins (_: cfg.grammars);
      setupModule = "nvim-treesitter";
      event = ["BufReadPost" "BufNewFile"];
      setupOpts = {
        ensure_installed = [];
        auto_install = false;
        sync_install = false;
        highlight = { enable = true; };
        indent = { enable = true; };
      } // cfg.setupOpts;
    };
  };
}
