{ config, lib, pkgs, colors, ... }:

let
  cfg = config.modules.yazi;
  yazi-plugins = pkgs.fetchFromGitHub {
    owner = "yazi-rs";
    repo = "plugins";
    rev = "b12a9ab085a8c2fe2b921e1547ee667b714185f9";
    hash = "sha256-LWN0riaUazQl3llTNNUMktG+7GLAHaG/IxNj1gFhDRE=";

  };
  glow-plugin = pkgs.fetchFromGitHub {
    owner = "Reledia";
    repo = "glow.yazi";
    rev = "2da96e3ffd9cd9d4dd53e0b2636f83ff69fe9af0";
    hash = "sha256-4krck4U/KWmnl32HWRsblYW/biuqzDPysrEn76buRck=";
  };
  duckdb-plugin = pkgs.fetchFromGitHub {
    owner = "wylie102";
    repo = "duckdb.yazi";
    rev = "ee8cae3bcddfaf4467ef72791239afbd3309c007";
    hash = "sha256-luVxgzRa21AykwQs/F8DB4O6ENcsEgF+Eb7dAkl0jhs=";
  };
  bat-plugin = pkgs.fetchFromGitHub {
    owner = "mgumz";
    repo = "yazi-plugin-bat";
    rev = "190b898e2073231aff8f2d621131d5215b796e8a";
    hash = "sha256-GKIEiFp9y8mAjbqoAU2wXPnDkeObMcNczs9xKz+naIU=";
  };
  mediainfo-plugin = pkgs.fetchFromGitHub {
    owner = "boydaihungst";
    repo = "mediainfo.yazi";
    rev = "436cb5f04d6e5e86ddc0386527254d87b7751ec8";
    hash = "sha256-oFp8mJ62FsJX46mKQ7/o6qXPC9qx3+oSfqS0cKUZETI=";
  };
  torrent-preview-plugin = pkgs.fetchFromGitHub {
    owner = "kirasok";
    repo = "torrent-preview.yazi";
    rev = "4ca5996a8264457cbefff8e430acfca4900a0453";
    hash = "sha256-vaeOdNa56wwzBV6DgJjprRlrAcz2yGUYsOveTJKFv6M=";
  };
  relative-motions-plugin = pkgs.fetchFromGitHub {
    owner = "dedukun";
    repo = "relative-motions.yazi";
    rev = "ce2e890227269cc15cdc71d23b35a58fae6d2c27";
    hash = "sha256-Ijz1wYt+L+24Fb/rzHcDR8JBv84z2UxdCIPqTdzbD14=";
  };
  lazygit-plugin = pkgs.fetchFromGitHub {
    owner = "Lil-Dank";
    repo = "lazygit.yazi";
    rev = "7a08a0988c2b7481d3f267f3bdc58080e6047e7d";
    hash = "sha256-OJJPgpSaUHYz8a9opVLCds+VZsK1B6T+pSRJyVgYNy8=";
  };
  augment-command-plugin = pkgs.fetchFromGitHub {
    owner = "hankertrix";
    repo = "augment-command.yazi";
    rev = "adebde061a891c01e6a25b349ade3cdb7e492e29";
    hash = "sha256-/x27CTosS6tz6vIKqbc+xzjwSrHYh6FGc/QdYokggj0=";
  };
  yaziline-plugin = pkgs.fetchFromGitHub {
    owner = "llanosrocas";
    repo = "yaziline.yazi";
    rev = "1342efed87fe7e408d44b6795ff3a62a478b381d";
    hash = "sha256-95l2jgE9lvJl6eZXuo+AThn2HE380rQtUG5LRnBZorc=";
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
        plugin = {
          prepend_preloaders = [
            {
              name = "*.csv";
              run = "duckdb";
              multi = false;
            }
            {
              name = "*.tsv";
              run = "duckdb";
              multi = false;
            }
            {
              name = "*.json";
              run = "duckdb";
              multi = false;
            }
            {
              name = "*.parquet";
              run = "duckdb";
              multi = false;
            }
            {
              name = "*.db";
              run = "duckdb";
            }
            {
              name = "*.duckdb";
              run = "duckdb";
            }
            {
              mime = "{audio,video,image}/*";
              run = "mediainfo";
            }
            {
              mime = "application/subrip";
              run = "mediainfo";
            }
          ];
          prepend_previewers = [
            {
              name = "*.md";
              run = "glow";
            }
            {
              name = "*.csv";
              run = "duckdb";
            }
            {
              name = "*.tsv";
              run = "duckdb";
            }
            {
              name = "*.json";
              run = "bat";
            }
            {
              name = "*.parquet";
              run = "duckdb";
            }
            {
              name = "*/";
              run = "folder";
              sync = true;
            }
            {
              mime = "text/*";
              run = "bat";
            }
            {
              mime = "*/xml";
              run = "bat";
            }
            {
              mime = "*/cs";
              run = "bat";
            }
            {
              mime = "*/javascript";
              run = "bat";
            }
            {
              mime = "*/x-wine-extension-ini";
              run = "bat";
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
        chmod = "${yazi-plugins}/chmod.yazi";
        mount = "${yazi-plugins}/mount.yazi";
        "jump-to-char" = "${yazi-plugins}/jump-to-char.yazi";
        "smart-filter" = "${yazi-plugins}/smart-filter.yazi";
        "vcs-files" = "${yazi-plugins}/vcs-files.yazi";
        diff = "${yazi-plugins}/diff.yazi";
        "toggle-pane" = "${yazi-plugins}/toggle-pane.yazi";
        glow = "${glow-plugin}";
        duckdb = "${duckdb-plugin}";
        bat = "${bat-plugin}";
        mediainfo = "${mediainfo-plugin}";
        "torrent-preview" = "${torrent-preview-plugin}";
        "relative-motions" = "${relative-motions-plugin}";
        "lazygit" = "${lazygit-plugin}";
        "augment-command" = "${augment-command-plugin}";
        "yaziline" = "${yaziline-plugin}";
      };
      initLua = ''
        require("duckdb"):setup()
        require("relative-motions"):setup({ show_numbers="relative", show_motion = true })
        require("augment-command"):setup({
          smart_tab_create = true,
          smooth_scrolling = true,
        })
      require("yaziline"):setup({
        color = "${colors.mocha.teal}",
        separator_style = "curvy",
      })
      '';
      keymap = {
        input.prepend_keymap = [
          { on = "<esc>"; run = "close"; desc = "Cancel input"; }
        ];
        manager.prepend_keymap = [
          { on = ["c" "m"]; run = "plugin chmod"; desc = "sha256-Ijz1wYt+L+24Fb/rzHcDR8JBv84z2UxdCIPqTdzbD14=Chmod on selected files"; }
          { on = "M"; run = "plugin mount"; desc = "Mount disk"; }
          { on = "f"; run = "plugin jump-to-char"; desc = "Jump to char"; }
          { on = "F"; run = "plugin smart-filter"; desc = "Smart filter"; }
          { on = ["g" "c"]; run = "plugin vcs-files"; desc = "Show Git file changes"; }
          { on = "<c-d>"; run = "plugin diff"; desc = "Diff the selected with the hovered file"; }
          { on = "T"; run = "plugin toggle-pane max-preview"; desc = "Maximize or restore the preview pane"; }
          { on = "t"; run = "plugin toggle-pane min-preview"; desc = "Show or hide the preview pane"; }
          { on = "H"; run = "plugin duckdb -1"; desc = "Scroll one column to the left"; }
          { on = "L"; run = "plugin duckdb +1"; desc = "Scroll one column to the right"; }
          { on = "<c-e>"; run = "seek 5"; }
          { on = "<c-y>"; run = "seek -5"; }
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
    home.packages = with pkgs; [
      glow
      duckdb
      mediainfo
    ];
    catppuccin.yazi = {
      enable = true;
      accent = "blue";
    };
  };
}
