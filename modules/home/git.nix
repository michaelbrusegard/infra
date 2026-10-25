{
  pkgs,
  config,
  lib,
  ...
}: let
  hasGithubToken = config.secrets ? keys && config.secrets.keys ? githubTokenFile;
  githubToken = config.sops.placeholder."keys/github-token";
in {
  programs = {
    git = {
      enable = true;
      lfs.enable = true;

      signing = {
        format = "ssh";
        key = config.secrets.ssh.gitKeyFile;
        signByDefault = true;
      };

      ignores =
        [
          "*.swp"
          "*.swo"
          ".env"
          ".direnv"
          "node_modules"
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
          ".DS_Store"
        ];

      settings = {
        user = {
          name = "Michael Brusegard";
          email = config.secrets.git.email;
        };

        init.defaultBranch = "main";
        push.autoSetupRemote = true;
        pull.rebase = false;

        status = {
          showUntrackedFiles = "all";
          showStash = true;
        };

        rebase.autoStash = true;

        core.editor = "nvim";

        merge = {
          conflictstyle = "merge";
          tool = "nvimdiff";
        };

        "mergetool \"nvimdiff\"" = {
          cmd = "nvim -c 'DiffviewOpen -uno'";
        };

        mergetool.prompt = false;

        diff.colorMoved = "default";

        "gpg \"ssh\"" = {
          allowedSignersFile = "${config.home.homeDirectory}/.config/git/allowed_signers";
        };

        rerere.enabled = true;
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
          pagers = [
            {
              pager = "delta --dark --paging=never";
              colorArg = "always";
            }
          ];
          parseEmoji = true;
        };

        disableStartupPopups = true;
        quitOnTopLevelReturn = true;
        os.editPreset = "nvim-remote";
      };
    };
    gh = {
      enable = true;
      extensions = with pkgs; [gh-eco gh-poi gh-dash gh-skyline gh-stack];
    };

    gh-dash = {
      enable = true;
      settings = {
        keybindings = {
          universal = [
            {
              key = "g";
              name = "lazygit";
              command = "cd {{.RepoPath}} && lazygit";
            }
          ];
        };
      };
    };
  };

  home = {
    file.".config/git/allowed_signers".text = ''
      ${config.secrets.git.email} namespaces="git" ${config.secrets.ssh.gitPublicKey}
    '';

    packages = with pkgs; [
      git-filter-repo
      git-lfs
    ];
  };

  # gh, its extensions, and its git credential helper all read the token from
  # hosts.yml, so it never has to be exported into every shell.
  sops.templates = lib.mkIf hasGithubToken {
    "gh-hosts.yml" = {
      path = "${config.xdg.configHome}/gh/hosts.yml";
      content = ''
        github.com:
            users:
                michaelbrusegard:
                    oauth_token: ${githubToken}
            oauth_token: ${githubToken}
            user: michaelbrusegard
      '';
    };
    npmrc = {
      path = "${config.home.homeDirectory}/.npmrc";
      content = ''
        //npm.pkg.github.com/:_authToken=${githubToken}
      '';
    };
  };
}
