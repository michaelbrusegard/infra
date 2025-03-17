{ config, lib, pkgs, catppuccin, ... }:

let
  cfg = config.modules.git;
in {
  options.modules.git.enable = lib.mkEnableOption "git configuration";

  config = lib.mkIf cfg.enable {
    programs = {
      git = {
        enable = true;
        userName = "Michael Brusegard";
        userEmail = "56915010+michaelbrusegard@users.noreply.github.com";
        extraConfig = {
          init = {
            defaultBranch = "main";
          };
          push = {
            autoSetupRemote = true;
          };
          pull = {
            rebase = false;
          };
          status = {
            showUntrackedFiles = "all";
            showStash = true;
          };
          rebase = {
            autoStash = true;
          };
          core = {
            editor = "nvim";
            pager = "delta";
          };
          commit = {
            gpgSign = true;
            signingKey = "~/.ssh/github_ed25519";
          };
          gpg = {
            format = "ssh";
          };
          merge = {
            conflictstyle = "diff3";
          };
          diff = {
            colorMoved = "default";
          };
          interactive = {
            diffFilter = "delta --color-only";
          };
        };
        delta = {
          enable = true;
          options = {
            navigate = true;
            side-by-side = true;
          };
        };
        ignores = [
          ".DS_Store"
          "*.swp"
          "*.swo"
          ".env"
          "node_modules"
        ];
      };
      catppuccin.delta.enable = true;
      lazygit = {
        enable = true;
        settings = {
          gui = {
            scrollOffMargin = 8;
            skipNoStagedFilesWarning = true;
            sidePanelWidth = 0.25;
            expandFocusedSidePanel = true;
            expandedSidePanelWeight = 2;
            language = "en";
            timeFormat = "02.01.2006";
            shortTimeFormat = "15:04";
            showBottomLine = false;
            showPanelJumps = false;
            nerdFontsVersion = "3";
          };
          git = {
            paging = {
              colorArg = "always";
              pager = "delta --dark --paging=never";
            };
            parseEmoji = true;
          };
          quitOnTopLevelReturn = true;
          os.editPreset = "nvim-remote";
        };
      };
      catppuccin.lazygit = {
        enable = true;
        accent = "blue";
      };
    };
  };
};
