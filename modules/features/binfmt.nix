{
  flake.modules.nixos.binfmt = {
    boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  };
}
