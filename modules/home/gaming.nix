{
  pkgs,
  lib,
  config,
  isWsl,
  homePersistenceRoot ? null,
  nvidiaOffload ? false,
  gamemodeRun ? false,
  ...
}: let
  enable = pkgs.stdenv.hostPlatform.isLinux && !isWsl;

  gamemoderun = lib.getExe' pkgs.gamemode "gamemoderun";

  # PRIME offload env so the launcher and its child game processes render on
  # the NVIDIA dGPU instead of the iGPU.
  offloadEnv = {
    __NV_PRIME_RENDER_OFFLOAD = "1";
    __NV_PRIME_RENDER_OFFLOAD_PROVIDER = "NVIDIA-G0";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    __VK_LAYER_NV_optimus = "NVIDIA_only";
  };

  envArgs = lib.concatStringsSep " " (
    lib.mapAttrsToList (k: v: "--set ${k} ${lib.escapeShellArg v}") offloadEnv
  );

  # Wrap a launcher so games render on the dGPU (offload env) and run under
  # GameMode (perf tuning + touchpad DWT toggle). Child game processes inherit
  # both. No-op when neither is requested.
  wrap = pkg: bin:
    if !(nvidiaOffload || gamemodeRun)
    then pkg
    else
      pkgs.symlinkJoin {
        name = "${pkg.pname or pkg.name}-wrapped";
        paths = [pkg];
        nativeBuildInputs = [pkgs.makeWrapper];
        postBuild = ''
          target=$(readlink -f $out/bin/${bin})
          rm $out/bin/${bin}
          ${
            if gamemodeRun
            then ''makeWrapper ${gamemoderun} $out/bin/${bin} --add-flags "$target" ${envArgs}''
            else ''makeWrapper "$target" $out/bin/${bin} ${envArgs}''
          }
        '';
      };

  launchers = [
    (wrap pkgs.prismlauncher "prismlauncher") # Minecraft
    (wrap pkgs.heroic "heroic") # Epic, GOG, Amazon
    (wrap pkgs.lutris "lutris") # Battle.net, EA, Ubisoft, emulators
  ];

  tools = [
    pkgs.mangohud # in-game FPS/CPU/GPU overlay
    pkgs.protonup-qt # manage Proton-GE across Steam/Heroic/Lutris
    pkgs.protontricks # winetricks fixes for Proton prefixes
    pkgs.vkbasalt # Vulkan post-processing (sharpening, etc.)
  ];

  # Perf + thermals overlay. Loaded but hidden by default (no_display);
  # press Shift_R+F12 in-game to show/hide it.
  mangohudConf = ''
    fps
    frametime
    frame_timing
    gpu_stats
    gpu_temp
    gpu_power
    cpu_stats
    cpu_temp
    ram
    vram
    gpu_name
    engine_version
    vulkan_driver
    position=top-left
    font_size=20
    background_alpha=0.4
    no_display=1
    toggle_hud=Shift_R+F12
    toggle_fps_limit=Shift_R+F11
  '';
  # Prism keeps its settings in a runtime-mutable cfg, so seed just the keys we
  # care about (idempotently) rather than managing the whole file. Feral
  # GameMode makes Prism run Minecraft itself under GameMode (perf); MangoHud
  # enables the overlay for the game (toggle it in-game with Shift_R+F12).
  prismCfg = "${config.home.homeDirectory}/.local/share/PrismLauncher/prismlauncher.cfg";
  setPrismKey = key: ''
    if [ -f "${prismCfg}" ]; then
      if grep -q '^${key}=' "${prismCfg}"; then
        $DRY_RUN_CMD sed -i 's/^${key}=.*/${key}=true/' "${prismCfg}"
      else
        $DRY_RUN_CMD printf '${key}=true\n' >> "${prismCfg}"
      fi
    fi
  '';
in {
  home =
    {
      packages = lib.optionals enable (launchers ++ tools);
    }
    // lib.optionalAttrs enable {
      file.".config/MangoHud/MangoHud.conf".text = mangohudConf;

      activation.prismGamingTweaks = lib.hm.dag.entryAfter ["writeBoundary"] ''
        ${setPrismKey "EnableFeralGamemode"}
        ${setPrismKey "EnableMangoHud"}
      '';
    }
    // lib.optionalAttrs (enable && homePersistenceRoot != null) {
      persistence = {
        ${homePersistenceRoot}.directories = [
          ".local/share/PrismLauncher"
          ".local/share/Steam"
          ".steam"
          ".config/heroic"
          ".local/share/lutris"
          ".config/lutris"
          ".local/share/Steam/compatibilitytools.d"
        ];
      };
    };
}
