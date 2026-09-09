{
  lib,
  callPackage,
  dockerTools,
  buildEnv,
  runCommand,
  busybox,
  curl,
  cacert,
  tzdata,
  nativeScim ? false,
}: let
  server = callPackage ./default.nix {inherit nativeScim;};
  layout = runCommand "stalwart-oss-image-layout" {} ''
    mkdir -p $out/usr/local/bin $out/var/lib/stalwart $out/tmp
    ln -s ${server}/bin/stalwart $out/usr/local/bin/stalwart
    chmod 1777 $out/tmp
    ${lib.optionalString nativeScim ''
      mkdir -p $out/usr/local/share/stalwart
      ln -s ${callPackage ./webui.nix {}} $out/usr/local/share/stalwart/webui.zip
    ''}
  '';
in
  dockerTools.buildLayeredImage {
    name = server.pname;
    tag = server.version;
    contents = buildEnv {
      name = "stalwart-oss-root";
      paths = [layout busybox curl cacert tzdata];
      pathsToLink = ["/bin" "/etc" "/usr" "/var" "/tmp" "/share/zoneinfo"];
    };
    config = {
      Entrypoint = ["/usr/local/bin/stalwart"];
      Cmd = ["--config" "/var/lib/stalwart/config.json"];
      Env = [
        "PATH=/bin:/usr/local/bin"
        "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
        "TZDIR=${tzdata}/share/zoneinfo"
      ];
      WorkingDir = "/var/lib/stalwart";
      Labels = {
        "org.opencontainers.image.title" =
          if nativeScim
          then "Stalwart OSS with independent native SCIM"
          else "Stalwart OSS";
        "org.opencontainers.image.version" = server.version;
        "org.opencontainers.image.source" = "https://github.com/michaelbrusegard/infra";
        "org.opencontainers.image.licenses" = "AGPL-3.0-only";
      };
    };
  }
