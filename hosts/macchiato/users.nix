{ config, userName, ... }: {
  users.users = {
    ${userName}.openssh.authorizedKeys.keys = config.secrets.macchiato.ssh.authorizedKeys;
    zigbee2mqtt.extraGroups = [ "dialout" ];
  };
}
