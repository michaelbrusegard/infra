_: {
  flake.modules.nixos.deploy = {config, ...}: {
    users.users.deploy = {
      isNormalUser = true;
      extraGroups = ["wheel"];
      openssh.authorizedKeys.keys = config.secrets.users.deploy.openssh.authorizedKeys.keys;
    };
    security.sudo-rs.extraRules = [
      {
        users = ["deploy"];
        commands = [
          {
            command = "ALL";
            options = ["NOPASSWD"];
          }
        ];
      }
    ];
  };

  flake.modules.homeManager.deploy = {
    home.stateVersion = "25.11";
  };
}
