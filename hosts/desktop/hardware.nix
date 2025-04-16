{ pkgs, modulesPath, ... }: {
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
  hardware = {
    enableRedistributableFirmware = true;
    cpu.amd.updateMicrocode = true;
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        rocmPackages.clr.icd
      ];
    };
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
    fancontrol = {
      enable = true;
         config = ''
          INTERVAL=10
          DEVPATH=hwmon2=devices/platform/nct6775.656
          DEVNAME=hwmon2=nct6798
          FCTEMPS=hwmon2/pwm1=hwmon2/temp1_input
          FCFANS=hwmon2/pwm1=hwmon2/fan1_input
          MINTEMP=hwmon2/pwm1=0
          MAXTEMP=hwmon2/pwm1=10
          MINSTART=hwmon2/pwm1=255
          MINSTOP=hwmon2/pwm1=254
          MINPWM=hwmon2/pwm1=254
          MAXPWM=hwmon2/pwm1=255
        '';
    };
  };
}
