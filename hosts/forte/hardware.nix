{
  config,
  lib,
  pkgs,
  ...
}: let
  setKbdBacklightLow = pkgs.writeShellScript "set-kbd-backlight-low" ''
    echo 1 > /sys/class/leds/asus::kbd_backlight/brightness
  '';

  # Hibernate quirks: the touchpad (AMD GPIO 8) storms while wake-armed and
  # can abort hibernation, and the ITE aura controller keeps its sleep breathing
  # animation after resume until a USB re-attach re-initialises it.
  hibernateWakeupFix = pkgs.writeShellScript "forte-hibernate-wakeup-fix" ''
    [ "$2" = hibernate ] || exit 0
    touchpad=/sys/bus/i2c/devices/i2c-ASCF1A01:00/power/wakeup
    case "$1" in
      pre)
        echo disabled > "$touchpad" 2>/dev/null || :
        ;;
      post)
        echo enabled > "$touchpad" 2>/dev/null || :
        for d in /sys/bus/usb/devices/*; do
          [ "$(cat "$d/idVendor" 2>/dev/null)" = 0b05 ] || continue
          [ "$(cat "$d/idProduct" 2>/dev/null)" = 19b6 ] || continue
          echo 0 > "$d/authorized" 2>/dev/null || :
          sleep 1
          echo 1 > "$d/authorized" 2>/dev/null || :
        done
        ;;
    esac
  '';
in {
  security.protectKernelImage = lib.mkForce false;

  boot = {
    initrd.availableKernelModules = [
      "nvme"
      "xhci_pci"
      "usbhid"
      "usb_storage"
      "sd_mod"
    ];
    kernelModules = ["kvm-amd"];

    kernelParams = [
      "quiet"
      "nvidia-drm.modeset=1"
    ];
    consoleLogLevel = 3;

    initrd.luks.devices = {
      crypted.crypttabExtraOpts = ["tpm2-device=auto"];
      crypted-swap.crypttabExtraOpts = ["tpm2-device=auto"];
    };

    loader.systemd-boot.consoleMode = "2";
  };

  hardware = {
    enableRedistributableFirmware = true;
    cpu.amd.updateMicrocode = true;
    bluetooth.enable = true;

    graphics.enable = true;

    nvidia = {
      modesetting.enable = true;
      open = true;
      nvidiaSettings = true;
      powerManagement = {
        enable = true;
        finegrained = true;
      };
      dynamicBoost.enable = true;
      package = config.boot.kernelPackages.nvidiaPackages.production;
      prime = {
        offload = {
          enable = true;
          enableOffloadCmd = true;
        };
        amdgpuBusId = "PCI:101:0:0";
        nvidiaBusId = "PCI:100:0:0";
      };
    };
  };

  local = {
    # Render games on the RTX 5080 instead of the AMD iGPU (offload default).
    gaming.nvidiaOffload = true;

    hyprland = {
      lidSwitch.output = "eDP-1";

      monitors = [
        {
          output = "eDP-1";
          mode = "3840x2400@120";
          position = "0x0";
          scale = 2;
          bitdepth = 10;
          # The factory panel ICC drives color and overrides any `cm` preset, so
          # there is no `cm` here on purpose.
          icc = "${../../config/color-profiles/H7606WW_1002_834C420E_CMDEF.icm}";
        }
        {
          output = "";
          mode = "preferred";
          position = "auto";
          scale = 1;
        }
      ];
    };
  };

  services = {
    xserver.videoDrivers = ["nvidia"];
    asusd = {
      enable = true;
      auraConfigs."19b6".text = ''
        (
            config_name: "aura_19b6.ron",
            brightness: Low,
            current_mode: Static,
            builtins: {
                Static: (
                    mode: Static,
                    zone: r#None,
                    colour1: (
                        r: 255,
                        g: 255,
                        b: 255,
                    ),
                    colour2: (
                        r: 0,
                        g: 0,
                        b: 0,
                    ),
                    speed: Med,
                    direction: Right,
                ),
            },
            multizone_on: false,
            enabled: (
                states: [
                    (
                        zone: Keyboard,
                        boot: true,
                        awake: true,
                        sleep: false,
                        shutdown: false,
                    ),
                ],
            ),
        )
      '';
      asusdConfig.text = ''
        (
            charge_control_end_threshold: 80,
            base_charge_control_end_threshold: 80,
            disable_nvidia_powerd_on_battery: true,
            ac_command: "",
            bat_command: "",
            platform_profile_linked_epp: true,
            platform_profile_on_battery: Quiet,
            change_platform_profile_on_battery: true,
            platform_profile_on_ac: Performance,
            change_platform_profile_on_ac: true,
            profile_quiet_epp: Power,
            profile_balanced_epp: BalancePower,
            profile_custom_epp: Performance,
            profile_performance_epp: Performance,
            ac_profile_tunings: {},
            dc_profile_tunings: {},
            armoury_settings: {},
        )
      '';
    };

    power-profiles-daemon.enable = true;
    upower.enable = true;
    fwupd.enable = true;

    # Closing the lid locks + blanks the internal panel (handled in Hyprland
    # via local.hyprland.lidSwitch)
    logind.settings.Login = {
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      HandleLidSwitchDocked = "ignore";
    };
  };

  systemd = {
    sleep.settings.Sleep.HibernateMode = "shutdown";

    services."systemd-backlight@leds:asus::kbd_backlight".serviceConfig = {
      ExecStart = lib.mkForce ["" "${setKbdBacklightLow}"];
      ExecStop = lib.mkForce (lib.getExe' pkgs.coreutils "true");
    };
  };

  environment.etc."systemd/system-sleep/00-forte-hibernate-wakeup-fix".source = hibernateWakeupFix;

  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };
}
