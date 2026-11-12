{pkgs, ...}: let
  primaryName = "router.asgard.michaelbrusegard.com";
  certificate = "/var/lib/acme/midgard.michaelbrusegard.com";
in
  pkgs.testers.runNixOSTest {
    name = "smtp-backup";
    nodes = {
      # Cortado's real secondary-MX configuration, with fixture TLS material.
      backup = {lib, ...}: {
        imports = [../../hosts/cortado/smtp-backup.nix];
        options.secrets = lib.mkOption {type = lib.types.attrs;};
        config = {
          secrets.smtp-backup = {
            clientCertificateFile = "/var/lib/fixture/client.crt";
            clientKeyFile = "/var/lib/fixture/client.key";
          };
          virtualisation.diskSize = 12288;
          networking.firewall.allowedTCPPorts = [25];
          networking.extraHosts = "192.168.1.2 ${primaryName}";
          services.postfix.settings.main = {
            smtp_tls_CAfile = lib.mkForce "${certificate}/fullchain.pem";
            smtp_host_lookup = "native";
            minimal_backoff_time = "1s";
            maximal_backoff_time = "5s";
            queue_run_delay = "1s";
          };
          environment.systemPackages = [pkgs.python3];
        };
      };
      # Stands in for the primary edge's port-2525 handoff listener.
      primary = {lib, ...}: {
        networking.firewall.allowedTCPPorts = [25 2525];
        environment.systemPackages = [pkgs.openssl pkgs.python3];
        systemd.services.postfix.serviceConfig.PrivateTmp = lib.mkForce false;
        services.postfix = {
          enable = true;
          setSendmail = false;
          settings.main = {
            myhostname = primaryName;
            mydestination = [];
            mynetworks = [];
            relay_domains = ["manafishrov.com"];
            parent_domain_matches_subdomains = "";
            relay_recipient_maps = "";
            smtpd_relay_restrictions = "reject_unauth_destination";
            smtpd_recipient_restrictions = "check_recipient_access texthash:/tmp/rejected";
            smtpd_tls_cert_file = "/tmp/server.crt";
            smtpd_tls_key_file = "/tmp/server.key";
            smtpd_tls_security_level = "may";
            relay_transport = "capture";
            capture_destination_recipient_limit = 1;
          };
          extraMasterConf =
            builtins.readFile ../smtp-edge/backup-master.cf
            + ''
              capture unix - n n - 1 pipe
                flags= user=nobody argv=${pkgs.writeShellScript "capture" ''
                printf '%s\n' "$@" >> /tmp/delivered
                ${pkgs.coreutils}/bin/cat >> /tmp/delivered
              ''} ''${client_address} ''${client_helo} ''${sender} ''${recipient}
            '';
        };
      };
    };
    testScript = ''
      import shlex

      start_all()
      primary.wait_for_unit("multi-user.target")
      backup.wait_for_unit("multi-user.target")
      primary.succeed("openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/server.key -out /tmp/server.crt -days 2 -subj /CN=${primaryName} -addext subjectAltName=DNS:${primaryName}")
      primary.succeed("echo 'deleted@manafishrov.com REJECT removed recipient' > /tmp/rejected")
      for name in ["client", "rogue"]:
          primary.succeed(f"openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/{name}.key -out /tmp/{name}.crt -days 2 -subj /CN={name}")
      primary.succeed("mkdir -p /run/postfix; openssl x509 -in /tmp/client.crt -noout -fingerprint -sha256 | cut -d= -f2 | sed 's/$/ OK/' > /run/postfix/backup-client")

      def copy(source, destination):
          contents = primary.succeed("cat " + source)
          backup.succeed("mkdir -p $(dirname " + destination + "); printf %s " + shlex.quote(contents) + " > " + destination)

      # The primary's certificate doubles as the backup's served certificate and trust anchor.
      copy("/tmp/server.crt", "${certificate}/fullchain.pem")
      copy("/tmp/server.key", "${certificate}/key.pem")
      copy("/tmp/client.crt", "/var/lib/fixture/client.crt")
      copy("/tmp/client.key", "/var/lib/fixture/client.key")
      backup.succeed("chmod 600 ${certificate}/key.pem /var/lib/fixture/client.key; systemctl restart postfix")
      backup.wait_for_open_port(25)
      primary.succeed("systemctl stop postfix")

      def python(node, source):
          return node.succeed("python3 -c " + shlex.quote(source))

      # Outage: accept any address in served domains, nothing else, no XFORWARD.
      python(primary, """
      import smtplib
      with smtplib.SMTP('192.168.1.1', 25) as s:
          s.ehlo('original.example.test')
          assert 'xforward' not in s.esmtp_features
          assert s.docmd('XFORWARD', 'ADDR=203.0.113.1')[0] >= 500
          for recipient in ['user@sub.manafishrov.com', 'user@elsewhere.test', 'root@[192.168.1.1]', 'root@[IPv6:::1]']:
              s.mail('sender@outside.test')
              assert s.rcpt(recipient)[0] >= 500, recipient
              s.rset()
          s.sendmail('sender@outside.test', ['user@manafishrov.com', 'invented+tag@manafishrov.com'], 'Subject: outage\\r\\n\\r\\npersistent payload')
          s.sendmail('sender@outside.test', ['deleted@manafishrov.com'], 'Subject: removed recipient\\r\\n\\r\\nrejected payload')
      """)
      backup.wait_until_succeeds("test $(postqueue -j | wc -l) -eq 2")
      backup.shutdown()
      backup.start()
      backup.wait_for_unit("postfix.service")
      assert len(backup.succeed("postqueue -j").splitlines()) == 2

      # Only the pinned client identity may hand off mail with original peer metadata.
      primary.succeed("systemctl start postfix")
      primary.wait_for_open_port(2525)
      python(primary, """
      import smtplib, ssl
      for identity in [None, 'rogue']:
          ctx = ssl._create_unverified_context()
          if identity:
              ctx.load_cert_chain('/tmp/rogue.crt', '/tmp/rogue.key')
          with smtplib.SMTP('localhost', 2525) as s:
              s.ehlo()
              s.starttls(context=ctx)
              s.ehlo()
              s.docmd('XFORWARD', 'ADDR=203.0.113.1 HELO=forged.test')
              s.mail('sender@outside.test')
              assert s.rcpt('user@manafishrov.com')[0] >= 500
      ctx = ssl._create_unverified_context()
      ctx.load_cert_chain('/tmp/client.crt', '/tmp/client.key')
      with smtplib.SMTP('localhost', 2525) as s:
          s.ehlo()
          s.starttls(context=ctx)
          s.ehlo()
          s.mail('sender@outside.test')
          assert s.rcpt('user@outside.test')[0] >= 500
      """)

      # Recovery: valid mail arrives with the original client; rejected mail
      # produces no notice to the (usually forged) sender.
      backup.succeed("postqueue -f")
      primary.wait_until_succeeds("grep 'persistent payload' /tmp/delivered", timeout=60)
      captured = primary.succeed("cat /tmp/delivered")
      assert '192.168.1.2\noriginal.example.test\nsender@outside.test' in captured, captured
      assert 'invented+tag@manafishrov.com' in captured, captured
      assert 'rejected payload' not in captured, captured
      backup.wait_until_succeeds("test -z \"$(postqueue -j)\"")
      backup.succeed("journalctl -u postfix | grep 'to=<sender@outside.test>.*status=sent (backup MX sends no notices)'")

      # A reachable primary with the wrong TLS identity must leave mail queued.
      primary.succeed("postconf -e smtpd_tls_cert_file=/tmp/rogue.crt smtpd_tls_key_file=/tmp/rogue.key; systemctl restart postfix")
      python(primary, """
      import smtplib
      with smtplib.SMTP('192.168.1.1', 25) as s:
          s.sendmail('sender@outside.test', ['user@manafishrov.com'], 'Subject: TLS identity\\r\\n\\r\\nwrong-cert payload')
      """)
      backup.wait_until_succeeds("postqueue -j | grep -E 'certificate.*(failed|not verified)'", timeout=60)
      primary.fail("grep 'wrong-cert payload' /tmp/delivered")
      primary.succeed("postconf -e smtpd_tls_cert_file=/tmp/server.crt smtpd_tls_key_file=/tmp/server.key; systemctl restart postfix")
      backup.succeed("postqueue -f")
      primary.wait_until_succeeds("grep 'wrong-cert payload' /tmp/delivered", timeout=60)
      backup.wait_until_succeeds("test -z \"$(postqueue -j)\"")
    '';
  }
