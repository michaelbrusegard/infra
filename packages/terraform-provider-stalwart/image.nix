{
  stdenv,
  callPackage,
  dockerTools,
  busybox,
}: let
  provider = callPackage ./default.nix {};
  inherit (provider) version;
  # OpenTofu's unpacked filesystem mirror layout:
  # HOSTNAME/NAMESPACE/TYPE/VERSION/TARGET/terraform-provider-TYPE*.
  mirror = "provider-mirror/registry.opentofu.org/michaelbrusegard/stalwart/${version}/linux_${stdenv.hostPlatform.go.GOARCH}";
in
  dockerTools.buildLayeredImage {
    name = "terraform-provider-stalwart";
    tag = version;
    # busybox provides cp for the init container that fills the runner's mirror.
    contents = [busybox];
    # A real file, not a store symlink: the runner copies it out of the image.
    extraCommands = ''
      install -Dm555 ${provider}/bin/terraform-provider-stalwart \
        ${mirror}/terraform-provider-stalwart_v${version}
    '';
    config = {
      Env = ["PATH=/bin"];
      Labels = {
        "org.opencontainers.image.title" = "OpenTofu provider mirror for Stalwart";
        "org.opencontainers.image.version" = version;
        "org.opencontainers.image.source" = "https://github.com/michaelbrusegard/infra";
        "org.opencontainers.image.licenses" = "MIT";
      };
    };
  }
