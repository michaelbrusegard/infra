{ config, lib, pkgs, catppuccin ... }:

let
  cfg = config.modules.terminal.wezterm;
in {
  options.modules.terminal.wezterm = {
    enable = lib.mkEnableOption "Yazi configuration";
  };

  config = lib.mkIf cfg.enable {
    programs.yazi = {
      enable = true;
      enableZshIntegration = true;
      shellWrapperName = "y";
      settings = {
        manager = {
          sort_by = "alphabetical";
          sort_sensitive = true;
          sort_dir_first = true;
          linemode = "mtime";
          show_hidden = true;
          show_symlink = true;
          scrolloff = 8;
          mouse_events = [
            "click"
            "scroll"
            "touch"
            "move"
            "drag"
          ];
          title_format = "{cwd}";
        };
      };
      keymap = {
        input.prepend_keymap = [
          { on = "<Esc>"; run = "close";  desc = "Cancel input" }
        ];
      };
    };
    catppuccin.yazi = {
      enable = true;
      accent = "blue";
    };
  };
}
