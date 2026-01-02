{
  pkgs,
  config,
  ...
}: {
  users.users.ops = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    shell = pkgs.zsh;
    inherit (config.secrets.users.ops) hashedPasswordFile;
    openssh.authorizedKeys.keys = config.secrets.users.ops.openssh.authorizedKeys.keys;
  };
}
