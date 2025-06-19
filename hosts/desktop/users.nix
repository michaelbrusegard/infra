{ config, userName, ... }: {
  users.users.${userName}.openssh.authorizedKeys.keys = config.secrets.desktop.ssh.authorizedKeys;
}
