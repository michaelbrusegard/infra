{ config, lib, pkgs, catppuccin, ... }:

let
  cfg = config.modules.yazi;
  # yazi-plugins = pkgs.fetchFromGitHub {
  #   owner = "yazi-rs";
  #   repo = "plugins";
  #   rev = "cb6165b25515b653a70f72a67889579d190facfe";
  # };
  # glow-plugin = pkgs.fetchFromGitHub {
  #   owner = "Reledia";
  #   repo = "glow.yazi";
  #   rev = "c76bf4fb612079480d305fe6fe570bddfe4f99d3";
  # };
  # miller-plugin = pkgs.fetchFromGitHub {
  #   owner = "Reledia";
  #   repo = "miller.yazi";
  #   rev = "40e02654725a9902b689114537626207cbf23436";
  # };
  # hexyl-plugin = pkgs.fetchFromGitHub {
  #   owner = "Reledia";
  #   repo = "hexyl.yazi";
  #   rev = "228a9ef2c509f43d8da1847463535adc5fd88794";
  # };
  # mediainfo-plugin = pkgs.fetchFromGitHub {
  #   owner = "boydaihungst";
  #   repo = "mediainfo.yazi";
  #   rev = "447fe95239a488459cfdbd12f3293d91ac6ae0d7";
  # };
  # eza-preview-plugin = pkgs.fetchFromGitHub {
  #   owner = "ahkohd";
  #   repo = "eza-preview.yazi";
  #   rev = "6575a9a4806d8dc96ac75adf28791155551804fb";
  # };
  # torrent-preview-plugin = pkgs.fetchFromGitHub {
  #   owner = "kirasok";
  #   repo = "torrent-preview.yazi";
  #   rev = "4ca5996a8264457cbefff8e430acfca4900a0453";
  # };
  # relative-motions-plugin = pkgs.fetchFromGitHub {
  #   owner = "dedukun";
  #   repo = "relative-motions.yazi";
  #   rev = "810306563e1928855f5cf61f83801544e3eb3788";
  # };
  # rsync-plugin = pkgs.fetchFromGitHub {
  #   owner = "GianniBYoung";
  #   repo = "rsync.yazi";
  #   rev = "3f431aa388a645cc95b8292659949a77c280ed8b";
  # };
  # lazygit-plugin = pkgs.fetchFromGitHub {
  #   owner = "Lil-Dank";
  #   repo = "lazygit.yazi";
  #   rev = "9f924e34cde61d5965d6d620698b0b15436c8e08";
  # };
  # augment-command-plugin = pkgs.fetchFromGitHub {
  #   owner = "hankertrix";
  #   repo = "augment-command.yazi";
  #   rev = "5ae8424f2bdfa85a3da8e973c059227946d554c5";
  # };
  # yaziline-plugin = pkgs.fetchFromGitHub {
  #   owner = "llanosrocas";
  #   repo = "yaziline.yazi";
  #   rev = "e06c47f7fc7a1c679e3935b45013108dadd09c96";
  # };
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
          mouse_events = [
            "click"
            "scroll"
            "touch"
            "move"
            "drag"
          ];
          title_format = "{cwd}";
        };
        preview = {
          max_width = 1000;
          max_height = 1000;
        };
        plugin = {
          prepend_preloaders = [
            {
              mime = "{audio,video,image}/*";
              run = "mediainfo";
            }
            {
              mime = "application/subrip";
              run = "mediainfo";
            }
          ];
          prepend_fetchers = [
            {
              id = "git";
              name = "*";
              run = "git";
            }
            {
              id = "git";
              name = "*/";
              run = "git";
            }
            {
              id = "mime";
              name = "*";
              run = "mime-ext";
              prio = "high";
            }
          ];
          prepend_previewers = [
            {
              name = "*/";
              run = "eza-preview";
            }
            {
              name = "*.md";
              run = "glow";
            }
            {
              mime = "text/csv";
              run = "miller";
            }
            {
              name = "*";
              run = "hexyl";
            }
            {
              mime = "{audio,video,image}/*";
              run = "mediainfo";
            }
            {
              mime = "application/subrip";
              run = "mediainfo";
            }
            {
              mime = "application/bittorrent";
              run = "torrent-preview";
            }
          ];
        };
      };
      plugins = {
        # chmod = "${yazi-plugins}/chmod.yazi";
        # mount = "${yazi-plugins}/mount.yazi";
        # "jump-to-char" = "${yazi-plugins}/jump-to-char.yazi";
        # "smart-filter" = "${yazi-plugins}/smart-filter.yazi";
        # git = "${yazi-plugins}/git.yazi";
        # "vcs-files" = "${yazi-plugins}/vcs-files.yazi";
        # diff = "${yazi-plugins}/diff.yazi";
        # "mime-ext" = "${yazi-plugins}/mime-ext.yazi";
        # "toggle-pane" = "${yazi-plugins}/toggle-pane.yazi";
        # glow = "${glow-plugin}";
        # miller = "${miller-plugin}";
        # hexyl = "${hexyl-plugin}";
        # mediainfo = "${mediainfo-plugin}";
        # "eza-preview" = "${eza-preview-plugin}";
        # "torrent-preview" = "${torrent-preview-plugin}";
        # "relative-motions" = "${relative-motions-plugin}";
        # rsync = "${rsync-plugin}";
        # "lazygit" = "${lazygit-plugin}";
        # "augment-command" = "${augment-command-plugin}";
        # "yaziline" = "${yaziline-plugin}";
      };
      initLua = ''
        -- require("git"):setup()
        -- require("relative-motions"):setup({ show_numbers="relative", show_motion = true })
        -- require("augment-command"):setup({
        --   smart_tab_create = true,
        --   smooth_scrolling = true,
        -- })
        -- require("yaziline"):setup({
        --   color = "${catppuccin.flavors.mocha.blue}",
        --   separator_style = "curvy",
        --   select_symbol = "",
        --   yank_symbol = "󰆐",
        -- })
      '';
      keymap = {
        input.prepend_keymap = [
          { on = "<esc>"; run = "close";  desc = "Cancel input"; }
        ];
        manager.prepend_keymap = [
          # { on = [ "c" "m" ]; run = "plugin chmod";  desc = "Chmod on selected files"; }
          # { on = "M"; run = "plugin mount";  desc = "Mount disk"; }
          # { on = "f"; run = "plugin jump-to-char";  desc = "Jump to char"; }
          # { on = "F"; run = "plugin smart-filter";  desc = "Smart filter"; }
          # { on = [ "g" "c" ]; run = "plugin vcs-files";  desc = "Show Git file changes"; }
          # { on = "<c-d>"; run = "plugin diff";  desc = "Diff the selected with the hovered file"; }
          # { on = "T"; run = "plugin toggle-pane max-preview"; desc = "Maximize or restore the preview pane"; }
          # { on = "t"; run = "plugin toggle-pane min-preview"; desc = "Show or hide the preview pane"; }
          { on = "<c-e>"; run = "seek 5"; }
          { on = "<c-y>"; run = "seek -5"; }
          # { on = [ "<space>" "E" ]; run = "plugin eza-preview"; desc = "Toggle tree/list dir preview"; }
          # { on = "1"; run = "plugin relative-motions 1"; desc = "Move in relative steps"; }
          # { on = "2"; run = "plugin relative-motions 2"; desc = "Move in relative steps"; }
          # { on = "3"; run = "plugin relative-motions 3"; desc = "Move in relative steps"; }
          # { on = "4"; run = "plugin relative-motions 4"; desc = "Move in relative steps"; }
          # { on = "5"; run = "plugin relative-motions 5"; desc = "Move in relative steps"; }
          # { on = "6"; run = "plugin relative-motions 6"; desc = "Move in relative steps"; }
          # { on = "7"; run = "plugin relative-motions 7"; desc = "Move in relative steps"; }
          # { on = "8"; run = "plugin relative-motions 8"; desc = "Move in relative steps"; }
          # { on = "9"; run = "plugin relative-motions 9"; desc = "Move in relative steps"; }
          # { on = "R"; run = "plugin rsync"; desc = "Copy files using rsync"; }
          # { on = [ "<space>" "g" "g" ]; run = "plugin lazygit"; desc = "Run lazygit"; }
        ];
      };
    };
    home.packages = with pkgs; [
      glow
      miller
      hexyl
      poppler
      mediainfo
    ];
    catppuccin.yazi = {
      enable = true;
      accent = "blue";
    };
  };
}
