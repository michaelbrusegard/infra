inputs: _: prev:
let
  inherit (prev.stdenv.hostPlatform) system;
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit system;
    config.allowUnfree = true;
  };
in
{
  inherit (pkgs-unstable)
    aerospace
    jankyborders
    postgresql
    fluffychat
    fluxcd
    kubectl
    kubernetes-helm
    etcd
    opencloud-desktop
    signal-desktop
    netbird-ui
    netbird
    ;

  # The wrapper script this patches only exists in the Linux build.
  feishin = prev.feishin.overrideAttrs (
    old:
    prev.lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
      postFixup = (old.postFixup or "") + ''
        substituteInPlace $out/bin/feishin \
          --replace-fail 'exec -a "$0" ' 'unset ELECTRON_RUN_AS_NODE
        exec -a "$0" '
      '';
    }
  );
}
