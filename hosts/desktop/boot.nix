{ pkgs, apple-fonts, system, ... }: {
  boot = {
    kernelModules = [ 
      "kvm-amd"
    ];
    kernelParams = [
      "quiet"
      "loglevel=3"
      "video=DP-1:3440x1440@144e"
    ];
    consoleLogLevel = 3;
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
      timeout = 0;
    };
    plymouth = {
      enable = true;
      logo = pkgs.runCommand "empty.png" {} ''
        ${pkgs.graphicsmagick}/bin/gm convert -size 1x1 xc:transparent $out
      '';
      font = "${apple-fonts.packages.${system}.sf-pro}/share/fonts/truetype/SF-Pro.ttf";
    };
    initrd = {
      availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
      luks.devices = {
        "luks-c3fbdb7e-8668-43d3-ae74-1c8dd400f0d8".device = "/dev/disk/by-uuid/c3fbdb7e-8668-43d3-ae74-1c8dd400f0d8";
        "luks-3326ca76-4cad-48a9-9c88-6aadd59e63fa".device = "/dev/disk/by-uuid/3326ca76-4cad-48a9-9c88-6aadd59e63fa";
      };
    };
  };
  catppuccin.plymouth.enable = true;
}
