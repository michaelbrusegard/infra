{
  lib,
  dockerTools,
  buildEnv,
  runCommand,
  postfix,
  bash,
  curl,
  cacert,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  gawk,
}: let
  layout = runCommand "smtp-edge-layout" {} ''
    mkdir -p $out/{bin,etc,opt/smtp-edge,var/lib/postfix,run,tmp}
    chmod 1777 $out/tmp
    ln -s /run/postfix $out/etc/postfix
    for tool in ${postfix}/bin/*; do
      ln -s "$tool" $out/bin/
    done
    cat > $out/etc/passwd <<'EOF'
    root:x:0:0:root:/root:/bin/bash
    postfix:x:100:100:Postfix:/var/lib/postfix:/bin/false
    postdrop:x:101:101:Postfix submission:/var/empty:/bin/false
    mailforward:x:102:102:Mail delivery:/var/empty:/bin/false
    nobody:x:65534:65534:Unprivileged:/var/empty:/bin/false
    EOF
    cat > $out/etc/group <<'EOF'
    root:x:0:
    postfix:x:100:
    postdrop:x:101:
    mailforward:x:102:
    nogroup:x:65534:
    EOF
    printf 'passwd: files\ngroup: files\nhosts: files dns\n' > $out/etc/nsswitch.conf
    cp ${./main.cf} $out/opt/smtp-edge/main.cf
    chmod u+w $out/opt/smtp-edge/main.cf
    cat >> $out/opt/smtp-edge/main.cf <<'EOF'
    command_directory = ${postfix}/bin
    daemon_directory = ${postfix}/libexec/postfix
    meta_directory = ${postfix}/etc/postfix
    shlib_directory = no
    sendmail_path = ${postfix}/bin/sendmail
    mailq_path = ${postfix}/bin/mailq
    newaliases_path = ${postfix}/bin/newaliases
    EOF
    cp ${./master.cf} $out/opt/smtp-edge/master.cf
    cp ${./deliver.sh} $out/opt/smtp-edge/deliver.sh
    cp ${./entrypoint.sh} $out/bin/smtp-edge-entrypoint
    chmod 0555 $out/bin/smtp-edge-entrypoint $out/opt/smtp-edge/deliver.sh
    substituteInPlace $out/bin/smtp-edge-entrypoint \
      --replace-fail '#!/usr/bin/env bash' '#!${bash}/bin/bash'
  '';
in
  assert lib.assertMsg (postfix.version == "3.11.3") "smtp-edge requires qualified Postfix 3.11.3";
  assert lib.assertMsg (curl.version == "8.20.0") "smtp-edge requires qualified curl 8.20.0";
    dockerTools.buildLayeredImage {
      name = "smtp-edge";
      tag = "postfix-${postfix.version}-curl-${curl.version}";
      contents = buildEnv {
        name = "smtp-edge-root";
        paths = [layout bash curl cacert coreutils findutils gnugrep gnused gawk];
        pathsToLink = ["/bin" "/etc" "/opt" "/var" "/run" "/tmp"];
      };
      config = {
        Entrypoint = ["/bin/smtp-edge-entrypoint"];
        Env = ["PATH=/bin" "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"];
        User = "0:0";
        WorkingDir = "/var/lib/postfix";
        ExposedPorts."25/tcp" = {};
        Labels = {
          "org.opencontainers.image.title" = "Postfix SMTP edge";
          "org.opencontainers.image.version" = "${postfix.version}-curl-${curl.version}";
          "org.opencontainers.image.source" = "https://github.com/michaelbrusegard/infra";
        };
      };
    }
