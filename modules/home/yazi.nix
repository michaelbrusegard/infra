{ pkgs, ... }:

let
  yaziPlugins = pkgs.fetchFromGitHub {
    owner = "yazi-rs";
    repo = "plugins";
    rev = "2301ff803a033cd16d16e62697474d6cb9a94711";
    hash = "sha256-+lirIBXv3EvztE/1b3zHnQ9r5N3VWBCUuH3gZR52fE0=";
  };

  relativeMotions = pkgs.fetchFromGitHub {
    owner = "dedukun";
    repo = "relative-motions.yazi";
    rev = "a603d9ea924dfc0610bcf9d3129e7cba605d4501";
    hash = "sha256-9i6x/VxGOA3bB3FPieB7mQ1zGaMK5wnMhYqsq4CvaM4=";
  };

  augmentCommand = pkgs.fetchFromGitHub {
    owner = "hankertrix";
    repo = "augment-command.yazi";
    rev = "120406f79b6a5bf4db6120dd99c1106008ada5cf";
    hash = "sha256-t9X7cNrMR3fFqiM13COQbBDHYr8UKgxW708V6ndZVgY=";
  };

  yaziline = pkgs.fetchFromGitHub {
    owner = "llanosrocas";
    repo = "yaziline.yazi";
    rev = "e7042a8b4ee9de4ebfb6e4106a6edf346cef99fb";
    hash = "sha256-cwuPh2aMh0oj9HEGyvrvkNTguER6VoXjnFklCTNPoeY=";
  };

  lazygitPlugin = pkgs.fetchFromGitHub {
    owner = "Lil-Dank";
    repo = "lazygit.yazi";
    rev = "8f37dc5795f165021098b17d797c7b8f510aeca9";
    hash = "sha256-rR7SMTtQYrvQjhkzulDaNH/LAA77UnXkcZ50WwBX2Uw=";
  };
in
{
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
        mouse_events = [ "click" "scroll" "touch" "move" "drag" ];
        title_format = "{cwd}";
        ratio = [ 1 3 5 ];
      };

      preview = {
        max_width = 1000;
        max_height = 1000;
      };
    };

    plugins = {
      chmod = "${yaziPlugins}/chmod.yazi";
      mount = "${yaziPlugins}/mount.yazi";
      "jump-to-char" = "${yaziPlugins}/jump-to-char.yazi";
      "smart-filter" = "${yaziPlugins}/smart-filter.yazi";
      "vcs-files" = "${yaziPlugins}/vcs-files.yazi";
      diff = "${yaziPlugins}/diff.yazi";
      "toggle-pane" = "${yaziPlugins}/toggle-pane.yazi";

      "relative-motions" = relativeMotions;
      "augment-command" = augmentCommand;
      yaziline = yaziline;
      lazygit = lazygitPlugin;
    };

    initLua = ''
      require("relative-motions"):setup({
        show_numbers = "relative",
        show_motion = true,
      })

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

        { on = [ "c" "m" ]; run = "plugin chmod"; desc = "Chmod on selected files"; }
        { on = "M"; run = "plugin mount"; desc = "Mount disk"; }
        { on = "f"; run = "plugin jump-to-char"; desc = "Jump to char"; }
        { on = [ "g" "c" ]; run = "plugin vcs-files"; desc = "Show Git file changes"; }
        { on = "<c-d>"; run = "plugin diff"; desc = "Diff selected with hovered"; }

        { on = "T"; run = "plugin toggle-pane max-preview"; desc = "Maximize preview"; }
        { on = "t"; run = "plugin toggle-pane min-preview"; desc = "Toggle preview"; }

        { on = "1"; run = "plugin relative-motions 1"; }
        { on = "2"; run = "plugin relative-motions 2"; }
        { on = "3"; run = "plugin relative-motions 3"; }
        { on = "4"; run = "plugin relative-motions 4"; }
        { on = "5"; run = "plugin relative-motions 5"; }
        { on = "6"; run = "plugin relative-motions 6"; }
        { on = "7"; run = "plugin relative-motions 7"; }
        { on = "8"; run = "plugin relative-motions 8"; }
        { on = "9"; run = "plugin relative-motions 9"; }

        { on = [ "g" "g" ]; run = "plugin lazygit"; desc = "Run lazygit"; }
      ];
    };
  };

  home.packages = with pkgs; [
    poppler-utils
    resvg
  ];
}
