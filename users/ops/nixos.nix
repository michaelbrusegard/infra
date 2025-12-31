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
  };
  programs.zsh.enable = true;
}
