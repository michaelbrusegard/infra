{ inputs, ... }: {
  flake.modules.nixos.dialpad =
    { lib, users, ... }:
    {
      imports = [
        inputs.asus-dialpad-driver.nixosModules.default
      ];

      hardware.asus-dialpad-driver = {
        enable = true;
        layout = "proartp16";
        sessionTypes = [ "wayland" ];
        # Replaces the module's defaults, which pin wayland-0. That socket
        # belongs to the greeter here, and uwsm already hands the session's own
        # display variables to every user service.
        environment.LOG = "WARNING";
      };

      # The driver runs in the user session and creates its virtual device
      # through /dev/uinput.
      users.users = lib.optionalAttrs (builtins.elem "michaelbrusegard" users) {
        michaelbrusegard.extraGroups = [ "uinput" ];
      };
    };
}
