{ pkgs, config, lib, pkgs-unstable, ... }:

let
  cfg = config.modules.yazi;
  yazi-plugins = pkgs-unstable.fetchFromGitHub {
    owner = "yazi-rs";
    repo = "plugins";
    rev = "2301ff803a033cd16d16e62697474d6cb9a94711";
    hash = "sha256-+lirIBXv3EvztE/1b3zHnQ9r5N3VWBCUuH3gZR52fE0=";

  };
  relative-motions-plugin = pkgs-unstable.fetchFromGitHub {
    owner = "dedukun";
    repo = "relative-motions.yazi";
    rev = "a603d9ea924dfc0610bcf9d3129e7cba605d4501";
    hash = "sha256-9i6x/VxGOA3bB3FPieB7mQ1zGaMK5wnMhYqsq4CvaM4=";
  };
  augment-command-plugin = pkgs-unstable.fetchFromGitHub {
    owner = "hankertrix";
    repo = "augment-command.yazi";
    rev = "120406f79b6a5bf4db6120dd99c1106008ada5cf";
    hash = "sha256-t9X7cNrMR3fFqiM13COQbBDHYr8UKgxW708V6ndZVgY=";
  };
  yaziline-plugin = pkgs-unstable.fetchFromGitHub {
    owner = "llanosrocas";
    repo = "yaziline.yazi";
    rev = "e7042a8b4ee9de4ebfb6e4106a6edf346cef99fb";
    hash = "sha256-cwuPh2aMh0oj9HEGyvrvkNTguER6VoXjnFklCTNPoeY=";
  };
  lazygit-plugin = pkgs-unstable.fetchFromGitHub {
    owner = "Lil-Dank";
    repo = "lazygit.yazi";
    rev = "8f37dc5795f165021098b17d797c7b8f510aeca9";
    hash = "sha256-rR7SMTtQYrvQjhkzulDaNH/LAA77UnXkcZ50WwBX2Uw=";
  };
in {
  options.modules.yazi.enable = lib.mkEnableOption "Yazi configuration";

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
          mouse_events = ["click" "scroll" "touch" "move" "drag"];
          title_format = "{cwd}";
          ratio = [ 1 3 5 ];
        };
        preview = {
          max_width = 1000;
          max_height = 1000;
        };
      };
      plugins = {
        chmod = "${yazi-plugins}/chmod.yazi";
        mount = "${yazi-plugins}/mount.yazi";
        "jump-to-char" = "${yazi-plugins}/jump-to-char.yazi";
        "smart-filter" = "${yazi-plugins}/smart-filter.yazi";
        "vcs-files" = "${yazi-plugins}/vcs-files.yazi";
        diff = "${yazi-plugins}/diff.yazi";
        "toggle-pane" = "${yazi-plugins}/toggle-pane.yazi";
        "relative-motions" = "${relative-motions-plugin}";
        "augment-command" = "${augment-command-plugin}";
        "yaziline" = "${yaziline-plugin}";
        "lazygit" = "${lazygit-plugin}";
      };
      initLua = ''
        require("relative-motions"):setup({ show_numbers="relative", show_motion = true })
        require("augment-command"):setup({
          smart_tab_create = true,
          smooth_scrolling = true,
        })
        require("yaziline"):setup({
          color = "${pkgs.catppuccin.mocha.teal}",
          separator_style = "curvy",
        })
      '';
      keymap = {
        input.prepend_keymap = [
          { on = "<esc>"; run = "close"; desc = "Cancel input"; }
        ];
        mgr.prepend_keymap = [
          { on = "<c-e>"; run = "seek 5"; }
          { on = "<c-y>"; run = "seek -5"; }
          { on = ["c" "m"]; run = "plugin chmod"; desc = "Chmod on selected files"; }
          { on = "M"; run = "plugin mount"; desc = "Mount disk"; }
          { on = "f"; run = "plugin jump-to-char"; desc = "Jump to char"; }
          { on = ["g" "c"]; run = "plugin vcs-files"; desc = "Show Git file changes"; }
          { on = "<c-d>"; run = "plugin diff"; desc = "Diff the selected with the hovered file"; }
          { on = "T"; run = "plugin toggle-pane max-preview"; desc = "Maximize or restore the preview pane"; }
          { on = "t"; run = "plugin toggle-pane min-preview"; desc = "Show or hide the preview pane"; }
          { on = "1"; run = "plugin relative-motions 1"; desc = "Move in relative steps"; }
          { on = "2"; run = "plugin relative-motions 2"; desc = "Move in relative steps"; }
          { on = "3"; run = "plugin relative-motions 3"; desc = "Move in relative steps"; }
          { on = "4"; run = "plugin relative-motions 4"; desc = "Move in relative steps"; }
          { on = "5"; run = "plugin relative-motions 5"; desc = "Move in relative steps"; }
          { on = "6"; run = "plugin relative-motions 6"; desc = "Move in relative steps"; }
          { on = "7"; run = "plugin relative-motions 7"; desc = "Move in relative steps"; }
          { on = "8"; run = "plugin relative-motions 8"; desc = "Move in relative steps"; }
          { on = "9"; run = "plugin relative-motions 9"; desc = "Move in relative steps"; }
          { on = ["g" "g"]; run = "plugin lazygit"; desc = "Run lazygit"; }
        ];
      };
    };
    home.packages = with pkgs-unstable; [
      poppler-utils
      resvg
    ];
    catppuccin.yazi.enable = true;
  };
}
