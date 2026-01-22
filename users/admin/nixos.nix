{
  pkgs,
  config,
  ...
}: {
  users.users.admin = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    shell = pkgs.zsh;
    inherit (config.secrets.users.admin) hashedPasswordFile;
    openssh.authorizedKeys.keys = config.secrets.users.admin.openssh.authorizedKeys.keys;
  };
  programs.zsh.enable = true;
}
