{ config, lib, pkgs, ... }:

let
  cfg = config.modules.git;
in {
  options.modules.git.enable = lib.mkEnableOption "git configuration";

  config = lib.mkIf cfg.enable {
    programs = {
      git = {
        enable = true;
        lfs.enable = true;
        userName = "Michael Brusegard";
        userEmail = "56915010+michaelbrusegard@users.noreply.github.com";
        signing = {
          format = "ssh";
          key = "~/.ssh/id_github";
          # key = config.sops.secrets."hosts/github/sshKey".path;
          signByDefault = true;
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
          };
          merge = {
            conflictstyle = "diff3";
          };
          diff = {
            colorMoved = "default";
          };
        };
      };
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
    };
    home.packages = with pkgs; [
      git-filter-repo
      git-lfs
    ];
    catppuccin = {
      delta.enable = true;
      lazygit = {
        enable = true;
        accent = "blue";
      };
    };
  };
}
