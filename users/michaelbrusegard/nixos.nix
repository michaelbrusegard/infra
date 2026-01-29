{
  pkgs,
  config,
  ...
}: {
  users.users.michaelbrusegard = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager" "docker" "libvirtd"];
    shell = pkgs.zsh;
    inherit (config.secrets.users.michaelbrusegard) hashedPasswordFile;
    openssh.authorizedKeys.keys = config.secrets.users.michaelbrusegard.openssh.authorizedKeys.keys;
  };
  programs.zsh.enable = true;
}
