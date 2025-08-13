{ config, lib, pkgs, colors, ... }:

let
  cfg = config.modules.yazi;
  yazi-plugins = pkgs.fetchFromGitHub {
    owner = "yazi-rs";
    repo = "plugins";
    rev = "e95c7b384e7b0a9793fe1471f0f8f7810ef2a7ed";
    hash = "sha256-TUS+yXxBOt6tL/zz10k4ezot8IgVg0/2BbS8wPs9KcE=";

  };
  glow-plugin = pkgs.fetchFromGitHub {
    owner = "Reledia";
    repo = "glow.yazi";
    rev = "bd3eaa58c065eaf216a8d22d64c62d8e0e9277e9";
    hash = "sha256-mzW/ut/LTEriZiWF8YMRXG9hZ70OOC0irl5xObTNO40=";
  };
  duckdb-plugin = pkgs.fetchFromGitHub {
    owner = "wylie102";
    repo = "duckdb.yazi";
    rev = "3f8c8633d4b02d3099cddf9e892ca5469694ba22";
    hash = "sha256-XQM459V3HbPgXKgd9LnAIKRQOAaJPdZA/Tp91TSGHqY=";
  };
  bat-plugin = pkgs.fetchFromGitHub {
    owner = "mgumz";
    repo = "yazi-plugin-bat";
    rev = "4dea0a584f30247b8ca4183dc2bd38c80da0d7ea";
    hash = "sha256-OPa8afKLZaBFL69pq5itI8xRg7u05FJthst88t6HZo0=";
  };
  mediainfo-plugin = pkgs.fetchFromGitHub {
    owner = "boydaihungst";
    repo = "mediainfo.yazi";
    rev = "0e2ae47cfb2b7c7a32d714c753b1cebbaa75d127";
    hash = "sha256-CHigaujMHd1BuYyyxzI5B4ZYQhuH2YZptVVJToq39sY=";
  };
  torrent-preview-plugin = pkgs.fetchFromGitHub {
    owner = "kirasok";
    repo = "torrent-preview.yazi";
    rev = "f46528243c458de3ffce38c44607d5a0cde67559";
    hash = "sha256-VhJvNRKHxVla4v2JJeSnP0MOMBFSm4k7gfqjrHOMVlo=";
  };
  relative-motions-plugin = pkgs.fetchFromGitHub {
    owner = "dedukun";
    repo = "relative-motions.yazi";
    rev = "a603d9ea924dfc0610bcf9d3129e7cba605d4501";
    hash = "sha256-9i6x/VxGOA3bB3FPieB7mQ1zGaMK5wnMhYqsq4CvaM4=";
  };
  lazygit-plugin = pkgs.fetchFromGitHub {
    owner = "Lil-Dank";
    repo = "lazygit.yazi";
    rev = "8f37dc5795f165021098b17d797c7b8f510aeca9";
    hash = "sha256-rR7SMTtQYrvQjhkzulDaNH/LAA77UnXkcZ50WwBX2Uw=";
  };
  augment-command-plugin = pkgs.fetchFromGitHub {
    owner = "hankertrix";
    repo = "augment-command.yazi";
    rev = "120406f79b6a5bf4db6120dd99c1106008ada5cf";
    hash = "sha256-t9X7cNrMR3fFqiM13COQbBDHYr8UKgxW708V6ndZVgY=";
  };
  yaziline-plugin = pkgs.fetchFromGitHub {
    owner = "llanosrocas";
    repo = "yaziline.yazi";
    rev = "e7042a8b4ee9de4ebfb6e4106a6edf346cef99fb";
    hash = "sha256-cwuPh2aMh0oj9HEGyvrvkNTguER6VoXjnFklCTNPoeY=";
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
