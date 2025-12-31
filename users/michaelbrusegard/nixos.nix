{
  pkgs,
  config,
  ...
}: {
  users.users.michaelbrusegard = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager" "docker"];
    shell = pkgs.zsh;
    hashedPasswordFile = config.secrets.users.michaelbrusegard.hashedPasswordFile;
  };
  programs.zsh.enable = true;
}
