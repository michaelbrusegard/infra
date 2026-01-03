{
  pkgs,
  ...
}: {
  boot = {
    initrd.availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod"];
    kernelModules = ["kvm-amd" "nct6775"];
    kernelParams = ["quiet"];
    consoleLogLevel = 3;
    binfmt.emulatedSystems = [
      "aarch64-linux"
    ];
  };

  hardware = {
    enableRedistributableFirmware = true;
    cpu.amd.updateMicrocode = true;
    graphics = {
      enable = true;
      extraPackages = [pkgs.mesa.opencl];
    };
    fancontrol = {
      enable = true;
      # Fan 1 is all chassis fans. That includes the fan underneath the power supply, the fan at the back of the case and the two fans on top of the case.
      # Fan 2 is the two CPU fans behind the radiator.
      # Fan 3 is the two GPU fans at the bottom of the case.
      config = ''
        INTERVAL=10
        DEVPATH=hwmon2=devices/platform/nct6775.656 hwmon4=devices/platform/asus-ec-sensors hwmon9=devices/pci0000:00/0000:00:03.1/0000:0a:00.0/0000:0b:00.0/0000:0c:00.0
        DEVNAME=hwmon2=nct6798 hwmon4=asusec hwmon9=amdgpu
        FCTEMPS=hwmon2/pwm1=hwmon4/temp3_input hwmon2/pwm2=hwmon4/temp2_input hwmon2/pwm3=hwmon9/temp2_input
        FCFANS=hwmon2/pwm1=hwmon2/fan1_input hwmon2/pwm2=hwmon2/fan2_input hwmon2/pwm3=hwmon2/fan3_input
        MINTEMP=hwmon2/pwm1=30 hwmon2/pwm2=40 hwmon2/pwm3=40
        MAXTEMP=hwmon2/pwm1=75 hwmon2/pwm2=85 hwmon2/pwm3=85
        MINSTART=hwmon2/pwm1=100 hwmon2/pwm2=100 hwmon2/pwm3=100
        MINSTOP=hwmon2/pwm1=77 hwmon2/pwm2=30 hwmon2/pwm3=30
        MINPWM=hwmon2/pwm1=77 hwmon2/pwm2=30 hwmon2/pwm3=30
        MAXPWM=hwmon2/pwm1=255 hwmon2/pwm2=255 hwmon2/pwm3=255
        AVERAGE=hwmon2/pwm1=1 hwmon2/pwm2=1 hwmon2/pwm3=1
      '';
    };
  };
  environment.variables.RUSTICL_ENABLE = "radeonsi";

  environment.systemPackages = with pkgs; [
    lm_sensors
    pciutils
  ];
}
