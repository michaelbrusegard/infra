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
        signing = {
          format = "ssh";
          key = config.secrets.ssh.gitKeyFile;
          signByDefault = true;
        };
        ignores = [
          ".DS_Store"
          "*.swp"
          "*.swo"
          ".env"
          ".direnv"
          "node_modules"
        ];
        settings = {
          user = {
            name = "Michael Brusegard";
            email = "56915010+michaelbrusegard@users.noreply.github.com";
          };
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
            tool = "nvimdiff";
          };
          "mergetool \"nvimdiff\"" = {
            cmd = "nvim -c 'DiffviewOpen -uno'";
          };
          mergetool = {
            prompt = false;
          };
          diff = {
            colorMoved = "default";
          };
          rerere = {
            enabled = true;
          };
        };
      };
      delta = {
        enable = true;
        enableGitIntegration = true;
        options = {
          navigate = true;
          side-by-side = true;
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
            overrideGpg = true;
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
      lazygit.enable = true;
    };
  };
}
