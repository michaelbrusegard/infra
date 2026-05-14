_: {
  programs.nh = {
    enable = true;
    flake = "$HOME/Projects/infra";
    clean = {
      enable = true;
      extraArgs = "--keep 3 --keep-since 4d";
    };
  };
}
