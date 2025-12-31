{
  pkgs,
  config,
  ...
}: {
  users.users.michaelbrusegard = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager" "docker"];
    shell = pkgs.zsh;
    inherit (config.secrets.users.michaelbrusegard) hashedPasswordFile;
  };
  programs.zsh.enable = true;
}
