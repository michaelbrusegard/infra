{
  pkgs,
  config,
  ...
}: {
  users.users.michaelbrusegard = {
    home = "/Users/michaelbrusegard";
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = config.secrets.users.michaelbrusegard.openssh.authorizedKeys.keys;
  };
  programs.zsh.enable = true;
}
