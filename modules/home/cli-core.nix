{
  pkgs,
  lib,
  homePersistenceRoot ? null,
  ...
}: {
  programs = {
    fd = {
      enable = true;
      hidden = true;
      ignores = [
        ".git"
        ".DS_Store"
      ];
    };
    zoxide = {
      enable = true;
      enableZshIntegration = true;
      options = ["--cmd cd"];
    };
    eza = {
      enable = true;
      enableZshIntegration = true;
      colors = "always";
      git = true;
      icons = "always";
      extraOptions = [
        "-a"
        "-1"
      ];
    };
    bat = {
      enable = true;
      config = {
        color = "always";
        italic-text = "always";
        style = "numbers";
        pager = "delta";
        paging = "never";
        map-syntax = [
          ".ignore:.gitignore"
        ];
      };
    };
    fzf = {
      enable = true;
      enableZshIntegration = true;
      defaultCommand = "fd --hidden --strip-cwd-prefix --exclude .git --exclude .DS_Store";
      fileWidgetCommand = "fd --hidden --strip-cwd-prefix --exclude .git --exclude .DS_Store";
      fileWidgetOptions = [
        "--preview 'if [ -d {} ]; then eza --tree --color=always {} | head -200; elif file --mime-type {} | grep -q \"image/\"; then chafa -f iterm -s \${FZF_PREVIEW_COLUMNS}x\${FZF_PREVIEW_LINES} {}; else bat -n --color=always --line-range :500 {}; fi'"
      ];
      historyWidgetOptions = [
        "--sort"
        "--exact"
      ];
    };
    ripgrep.enable = true;
    jq.enable = true;
    btop.enable = true;
  };

  home =
    {
      packages = with pkgs; [
        # Network/transfer
        curl
        wget
        rsync
        rclone

        # Network diagnostics
        nmap
        netcat
        bind
        whois
        mtr

        # Secrets
        age
        sops
        ssh-to-age

        # Crypto
        openssl

        # Compression/archive
        zstd
        gnutar
        unzip

        # GNU/POSIX baseline
        uutils-coreutils
        findutils
        file

        # Sysadmin essentials
        yq
        lsof
      ];

      shellAliases = {
        ls = "eza";
        cat = "bat";
      };
    }
    // lib.optionalAttrs (homePersistenceRoot != null) {
      persistence.${homePersistenceRoot}.directories = [
        ".local/share/zoxide"
      ];
    };
}
