{
  lib,
  pkgs,
  ...
}: let
  # AMD-iGPU factory profile is the panel default. The 10DE_… variant is
  # the same profile for the NVIDIA dGPU path; ASUS_{sRGB,DisplayP3,DCIP3}
  # are nominal gamut targets matching the ProArt OSD presets.
  defaultProfile = "H7606WW_1002_834C420E_CMDEF.icm";

  profiles = {
    "ASUS_DCIP3.icm" = ./color-profiles/ASUS_DCIP3.icm;
    "ASUS_DisplayP3.icm" = ./color-profiles/ASUS_DisplayP3.icm;
    "ASUS_sRGB.icm" = ./color-profiles/ASUS_sRGB.icm;
    "H7606WW_1002_834C420E_CMDEF.icm" = ./color-profiles/H7606WW_1002_834C420E_CMDEF.icm;
    "H7606WW_10DE_834C420E_CMDEF.icm" = ./color-profiles/H7606WW_10DE_834C420E_CMDEF.icm;
  };

  bindProfile = pkgs.writeShellApplication {
    name = "forte-bind-default-icc";
    runtimeInputs = [pkgs.colord pkgs.gawk pkgs.coreutils];
    text = ''
      set -euo pipefail

      flag="''${XDG_STATE_HOME:-$HOME/.local/state}/forte-icc-bound"
      profile_path=/var/lib/colord/icc/${defaultProfile}

      if [ -e "$flag" ]; then
        exit 0
      fi

      if [ ! -e "$profile_path" ]; then
        printf 'profile not found: %s\n' "$profile_path" >&2
        exit 1
      fi

      colormgr import-profile "$profile_path" >/dev/null || true

      device_id=$(colormgr get-devices-by-kind display \
        | awk '/Object Path/ { id=$NF } /Embedded:.*Yes/ { print id; exit }')
      if [ -z "''${device_id:-}" ]; then
        printf 'no embedded display device found via colord; retry once Hyprland brings the panel up\n' >&2
        exit 1
      fi

      profile_id=$(colormgr find-profile-by-filename "$profile_path" \
        | awk '/Object Path/ { print $NF; exit }')
      if [ -z "''${profile_id:-}" ]; then
        printf 'colord did not surface the imported profile\n' >&2
        exit 1
      fi

      colormgr device-add-profile "$device_id" "$profile_id" || true
      colormgr device-make-profile-default "$device_id" "$profile_id"

      mkdir -p "$(dirname "$flag")"
      : > "$flag"
    '';
  };
in {
  services.colord.enable = true;

  systemd.tmpfiles.settings."10-forte-colord" = lib.mapAttrs' (name: path:
    lib.nameValuePair "/var/lib/colord/icc/${name}" {
      "L+" = {
        argument = "${path}";
      };
    })
  profiles;

  environment.persistence."/persistent".directories = [
    "/var/lib/colord"
  ];

  home-manager.sharedModules = [
    {
      systemd.user.services.forte-bind-default-icc = {
        Unit = {
          After = ["graphical-session.target"];
          PartOf = ["graphical-session.target"];
        };
        Install.WantedBy = ["graphical-session.target"];
        Service = {
          Type = "oneshot";
          ExecStart = "${bindProfile}/bin/forte-bind-default-icc";
        };
      };
    }
  ];
}
