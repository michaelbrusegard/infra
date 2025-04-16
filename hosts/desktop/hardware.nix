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
        DEVPATH=hwmon2=devices/platform/nct6775.656 hwmon4=devices/platform/asus-ec-sensors hwmon9=devices/pci0000:00/0000:00:03.1/0000:0a:00.0/0000:0b:00.0/0000:0c:00.0 
        DEVNAME=hwmon2=nct6798 hwmon4=asusec hwmon9=amdgpu 
        FCTEMPS=hwmon2/pwm6=hwmon4/temp2_input 
        FCFANS=hwmon2/pwm6=hwmon2/fan6_input 
        MINTEMP=hwmon2/pwm6=0 
        MAXTEMP=hwmon2/pwm6=100 
        MINSTART=hwmon2/pwm6=255 
        MINSTOP=hwmon2/pwm6=255 
        MINPWM=hwmon2/pwm6=255 
        MAXPWM=hwmon2/pwm6=255 
        AVERAGE=hwmon2/pwm6=1 
      '';
    };
  };
}
