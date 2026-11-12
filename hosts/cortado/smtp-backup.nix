{
  config,
  lib,
  pkgs,
  ...
}: let
  # Secondary MX: queue mail for these domains while Asgard is unreachable,
  # then hand it to the primary edge, which owns recipient checks and bounces.
  domains = ["manafishrov.com"];
  primary = "router.asgard.michaelbrusegard.com";
  certificate = "/var/lib/acme/midgard.michaelbrusegard.com";
  servedDomains = pkgs.writeText "smtp-backup-domains" (
    lib.concatMapStrings (domain: "/@${lib.replaceStrings ["."] ["[.]"] domain}$/ DUNNO\n") domains
    + "/.*/ REJECT recipient domain not served\n"
  );
in {
  services.postfix = {
    enable = true;
    setSendmail = false;
    settings.main = {
      myhostname = "router.midgard.michaelbrusegard.com";
      mydestination = [];
      mynetworks = [];
      relay_domains = domains;
      parent_domain_matches_subdomains = "";
      # Accept any address: the primary verifies recipients on handoff.
      relay_recipient_maps = "";
      # Postfix otherwise treats recipients at its own IP literals as local.
      smtpd_relay_restrictions = "check_recipient_access regexp:${servedDomains}, reject_unauth_destination";
      smtpd_sasl_auth_enable = false;
      disable_vrfy_command = true;
      smtpd_helo_required = true;
      smtpd_authorized_xforward_hosts = "";
      smtpd_authorized_xclient_hosts = "";
      smtpd_tls_security_level = "may";
      smtpd_tls_cert_file = "${certificate}/fullchain.pem";
      smtpd_tls_key_file = "${certificate}/key.pem";
      # A single explicit next hop prevents delivery looping back to this MX.
      relay_transport = "backup:[${primary}]:2525";
      smtp_tls_security_level = "secure";
      smtp_tls_secure_cert_match = "nexthop";
      smtp_tls_CAfile = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      # Client identity pinned by the primary's port-2525 handoff listener.
      smtp_tls_cert_file = config.secrets.smtp-backup.clientCertificateFile;
      smtp_tls_key_file = config.secrets.smtp-backup.clientKeyFile;
      smtp_fallback_relay = "";
      local_transport = "error:local delivery disabled";
      virtual_transport = "error:virtual delivery disabled";
      # Mail rejected by the primary is mostly spam to invented addresses with
      # forged senders. Dropping its notices avoids backscatter; this host
      # never sends mail to the Internet.
      default_transport = "discard:backup MX sends no notices";
      maximal_queue_lifetime = "14d";
      bounce_queue_lifetime = "14d";
      message_size_limit = 104857600;
      queue_minfree = 5368709120;
      default_process_limit = 20;
      smtp_destination_concurrency_limit = 2;
      smtpd_client_connection_count_limit = 5;
      smtpd_client_connection_rate_limit = 30;
      smtpd_client_message_rate_limit = 60;
      smtpd_recipient_limit = 100;
    };
    settings.master.backup = {
      command = "smtp";
      args = [
        "-o"
        "smtp_send_xforward_command=yes"
      ];
    };
  };

  systemd.services.postfix = {
    serviceConfig = {
      MemoryMax = "512M";
      CPUQuota = "50%";
      TasksMax = 100;
    };
  };

  # Activation gate: open WAN TCP 25 and publish the secondary MX only after
  # an external outage drill.
  # networking.firewall.interfaces.enp7s0.allowedTCPPorts = [25];
}
