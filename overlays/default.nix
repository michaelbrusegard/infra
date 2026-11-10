{inputs}: let
  inherit (inputs.nixpkgs.lib) composeManyExtensions;
in
  composeManyExtensions [
    (_: prev: import ../packages {pkgs = prev;})
    inputs.yazi.overlays.default
    inputs.brew-nix.overlays.default
    (_: prev:
      prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
        brewCasks =
          prev.brewCasks
          // {
            nimble-commander = prev.brewCasks.nimble-commander.overrideAttrs (old: {
              # Older DMGs move off magnumbytes.com; retain the cask's checksum.
              src = prev.fetchurl {
                inherit (old.src) name;
                url =
                  builtins.replaceStrings
                  ["https://magnumbytes.com/downloads/releases/"]
                  ["https://raw.githubusercontent.com/mikekazakov/nimble-commander-releases/main/"]
                  old.src.url;
                sha256 = old.src.outputHash;
              };
            });
          };
      })
    inputs.asus-dialpad-driver.overlays.default
    (import ./dialpad)
    (import ./flake-packages.nix inputs)
    (import ./firefox-darwin.nix)
    (import ./unstable-packages.nix inputs)
  ]
