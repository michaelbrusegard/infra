{ config, lib, pkgs, ... }:

let
  cfg = config.modules.terminal.git;
in {
  options.modules.terminal.git = {
    enable = lib.mkEnableOption "git configuration";
  };

  config = lib.mkIf cfg.enable {
    programs.git = {
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
  };
}
