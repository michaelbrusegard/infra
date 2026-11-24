{
  flake.modules.nixos.networking = {name, ...}: {
    networking.hostName = name;
  };

  flake.modules.darwin.networking = {name, ...}: {
    networking = {
      applicationFirewall = {
        enable = true;
        allowSigned = true;
        allowSignedApp = true;
      };
      hostName = name;
      computerName = name;
    };
  };
}
