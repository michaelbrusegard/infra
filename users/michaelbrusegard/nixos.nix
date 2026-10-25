{
  pkgs,
  config,
  lib,
  isWsl,
  ...
}: {
  imports = [../../modules/common/codex.nix];

  users.users.michaelbrusegard = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager" "docker" "libvirtd" "i2c" "input"];
    shell = pkgs.zsh;
    hashedPasswordFile = lib.mkIf (!isWsl) config.secrets.users.michaelbrusegard.hashedPasswordFile;
    openssh.authorizedKeys.keys = config.secrets.users.michaelbrusegard.openssh.authorizedKeys.keys;
  };
  programs.zsh.enable = true;
}
