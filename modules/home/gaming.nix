{
  pkgs,
  lib,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: let
  enable = pkgs.stdenv.isLinux && !isWsl;
in {
  home =
    {
      packages = lib.optionals enable [
        pkgs.prismlauncher # Minecraft
        pkgs.heroic # Epic, GOG, Amazon
        pkgs.lutris # Battle.net, EA, Ubisoft, emulators, standalone
        pkgs.mangohud # in-game FPS/CPU/GPU overlay
        pkgs.protonup-qt # manage Proton-GE across Steam/Heroic/Lutris
        pkgs.protontricks # winetricks fixes for Proton prefixes
        pkgs.vkbasalt # Vulkan post-processing (sharpening, etc.)
      ];
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
