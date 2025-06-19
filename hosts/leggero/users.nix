{ config, userName, ... }: {
  users.users.${userName}.openssh.authorizedKeys.keys = config.secrets.leggero.ssh.authorizedKeys;
}
