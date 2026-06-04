{config, ...}: {
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
      crypted1.crypttabExtraOpts = ["tpm2-device=auto"];
    };
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

  # Render games on the RTX 5080 instead of the AMD iGPU (offload default),
  # and lift touchpad disable-while-typing while a game runs.
  local.gaming = {
    nvidiaOffload = true;
    touchpadDwtToggle = true;
  };

  services = {
    xserver.videoDrivers = ["nvidia"];
    asusd = {
      enable = true;
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
                        sleep: true,
                        shutdown: true,
                    ),
                ],
            ),
        )
      '';
    };

    power-profiles-daemon.enable = true;
    upower.enable = true;
    fwupd.enable = true;
  };

  local.hyprland.monitors = [
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

  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };
}
