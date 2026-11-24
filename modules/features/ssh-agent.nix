{
  flake.modules.nixos.ssh-agent = {
    programs.ssh.startAgent = true;
  };
}
