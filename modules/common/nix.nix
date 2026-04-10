{inputs, ...}: {
  nix = {
    optimise.automatic = true;

    gc = {
      automatic = true;
      options = "--delete-older-than 7d";
    };

    settings = {
      builders-use-substitutes = true;
      extra-experimental-features = ["nix-command" "flakes"];

      substituters = [
        "https://cache.nixos.org?priority=10"
        "https://nix-community.cachix.org?priority=20"
        "https://nixos-raspberrypi.cachix.org?priority=30"
        "https://hyprland.cachix.org?priority=40"
        "https://wezterm.cachix.org?priority=50"
        "https://yazi.cachix.org?priority=60"
        "https://cache.garnix.io?priority=70"
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "wezterm.cachix.org-1:kAbhjYUC9qvblTE+s7S+kl5XM1zVa4skO+E/1IDWdH0="
        "yazi.cachix.org-1:Dcdz63NZKfvUCbDGngQDAZq6kOroIrFoyO064uvLh8k="
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      ];
    };
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [inputs.self.overlays.default];

  time.timeZone = "Europe/Oslo";
}
