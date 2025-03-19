{ modulesPath, ... }: {
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
  hardware = {
    enableRedistributableFirmware = true;
    cpu.amd.updateMicrocode = true;
    opengl = {
      enable = true;
      driSupport = true;
    };
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };
}
