# Records that decide where mail for both domains is delivered and who may
# send it. main.tf merges each domain's map into its zone's records.
locals {
  # macchiato's dyndns keeps this on the WAN address. The edge certificate
  # covers it and Stalwart's MTA-STS policy lists it.
  stalwart_mx = "mx.asgard.michaelbrusegard.com"
  # cortado (midgard) queues mail while asgard is unreachable and hands it
  # back over the pinned port-2525 handoff; it never delivers locally.
  stalwart_backup_mx = "router.midgard.michaelbrusegard.com"
  # Senders refetch the MTA-STS policy when this id changes: set it to the
  # date whenever the policy (Stalwart's stalwart_mta_sts) changes.
  mta_sts_id = "20261116"
  # SMTP2GO is the only outbound path; nothing sends from the MX. Its bounce
  # return path (em1206132) already carries the envelope SPF.
  stalwart_spf = "v=spf1 include:spf.smtp2go.com -all"
  # The policy host is the HTTPS Gateway, not the SMTP edge's split-DNS VIP.
  stalwart_mta_sts_host = "router.asgard.michaelbrusegard.com"

  # DMARC passes on Stalwart's and SMTP2GO's d=<domain> signatures. SPF only
  # aligns relaxed because SMTP2GO's envelope sender is the em1206132
  # subdomain.
  stalwart_mail = {
    michaelbrusegard = {
      mx = {
        name     = "michaelbrusegard.com"
        type     = "MX"
        content  = local.stalwart_mx
        priority = 10
        ttl      = 300
      }
      mx_secondary = {
        name     = "michaelbrusegard.com"
        type     = "MX"
        content  = local.stalwart_backup_mx
        priority = 20
        ttl      = 300
      }
      spf = {
        name     = "michaelbrusegard.com"
        type     = "TXT"
        content  = local.stalwart_spf
        priority = null
        ttl      = 300
      }
      dmarc = {
        name     = "_dmarc.michaelbrusegard.com"
        type     = "TXT"
        content  = "v=DMARC1; p=quarantine; adkim=s; rua=mailto:postmaster@michaelbrusegard.com"
        priority = null
        ttl      = 300
      }
      mta_sts = {
        name     = "mta-sts.michaelbrusegard.com"
        type     = "CNAME"
        content  = local.stalwart_mta_sts_host
        priority = null
        ttl      = 300
      }
      mta_sts_policy = {
        name     = "_mta-sts.michaelbrusegard.com"
        type     = "TXT"
        content  = "v=STSv1; id=${local.mta_sts_id}"
        priority = null
        ttl      = 300
      }
    }
    michbrus = {
      mx = {
        name     = "michbrus.com"
        type     = "MX"
        content  = local.stalwart_mx
        priority = 10
        ttl      = 300
      }
      mx_secondary = {
        name     = "michbrus.com"
        type     = "MX"
        content  = local.stalwart_backup_mx
        priority = 20
        ttl      = 300
      }
      spf = {
        name     = "michbrus.com"
        type     = "TXT"
        content  = local.stalwart_spf
        priority = null
        ttl      = 300
      }
      dmarc = {
        name     = "_dmarc.michbrus.com"
        type     = "TXT"
        content  = "v=DMARC1; p=quarantine; adkim=s; rua=mailto:postmaster@michbrus.com"
        priority = null
        ttl      = 300
      }
      mta_sts = {
        name     = "mta-sts.michbrus.com"
        type     = "CNAME"
        content  = local.stalwart_mta_sts_host
        priority = null
        ttl      = 300
      }
      mta_sts_policy = {
        name     = "_mta-sts.michbrus.com"
        type     = "TXT"
        content  = "v=STSv1; id=${local.mta_sts_id}"
        priority = null
        ttl      = 300
      }
      tlsrpt = {
        name     = "_smtp._tls.michbrus.com"
        type     = "TXT"
        content  = "v=TLSRPTv1; rua=mailto:postmaster@michbrus.com"
        priority = null
        ttl      = 300
      }
    }
  }
}
