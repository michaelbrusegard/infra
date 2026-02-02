{
  lib,
  isWsl,
  inputs,
  ...
}: {
  imports = lib.optionals (!isWsl) [
    inputs.zen-browser.homeModules.beta
    ./policies.nix
    ./extensions.nix
    ./preferences.nix
    ./profile.nix
    ./search.nix
    ./mods.nix
    ./containers.nix
    ./spaces.nix
    ./pins.nix
    ./shortcuts.nix
    ./mimeapps.nix
  ];
}
