data "cloudflare_zone" "michaelbrusegard" {
  filter = {
    name = "michaelbrusegard.com"
  }
}

locals {
  zone_id = data.cloudflare_zone.michaelbrusegard.zone_id

  # Safe records: no mail-flow impact. Stalwart DKIM selectors don't conflict
  # with any existing provider's selectors; TLSRPT is reporting-only. Safe to
  # publish before stalwart cutover.
  safe_records = {
    dkim_rsa = {
      name    = "stalwart-rsa._domainkey"
      type    = "TXT"
      content = "v=DKIM1; k=rsa; p=${var.dkim_rsa_pub_michaelbrusegard}"
    }
    dkim_ed25519 = {
      name    = "stalwart-ed25519._domainkey"
      type    = "TXT"
      content = "v=DKIM1; k=ed25519; p=${var.dkim_ed25519_pub_michaelbrusegard}"
    }
    tlsrpt = {
      name    = "_smtp._tls"
      type    = "TXT"
      content = "v=TLSRPTv1; rua=mailto:postmaster@michaelbrusegard.com"
    }
  }

  # Migration records: uncomment AFTER stalwart is verified working end-to-end
  # (bootstrap done, listeners up, test mail round-trips, DKIM passes). These
  # will steal mail-flow from any existing provider.
  #
  # The server hostname mail.gullhaugveien.michaelbrusegard.com is managed by
  # cloudflare-dyndns on macchiato (A+AAAA tracking WAN). The MX target must
  # resolve directly to an A record (RFC 5321 forbids MX-to-CNAME), so MX
  # points at the dyndns-managed name. Other apex-zone names (autoconfig,
  # autodiscover, mta-sts) CNAME to it.
  #
  # IPv6 omitted: cluster LB pool uses ULA fd7a:115c:a1e0:188::/64 which is
  # not internet-routable. v6 inbound mail requires assigning a GUA prefix to
  # the LB pool first.
  #
  # mail_records = {
  #   mta_sts = {
  #     name    = "mta-sts"
  #     type    = "CNAME"
  #     content = "mail.gullhaugveien.michaelbrusegard.com"
  #   }
  #   autoconfig = {
  #     name    = "autoconfig"
  #     type    = "CNAME"
  #     content = "mail.gullhaugveien.michaelbrusegard.com"
  #   }
  #   autodiscover = {
  #     name    = "autodiscover"
  #     type    = "CNAME"
  #     content = "mail.gullhaugveien.michaelbrusegard.com"
  #   }
  #   mx = {
  #     name     = "@"
  #     type     = "MX"
  #     content  = "mail.gullhaugveien.michaelbrusegard.com"
  #     priority = 10
  #   }
  #   spf = {
  #     name    = "@"
  #     type    = "TXT"
  #     content = "v=spf1 mx -all"
  #   }
  #   dmarc = {
  #     name    = "_dmarc"
  #     type    = "TXT"
  #     content = "v=DMARC1; p=quarantine; rua=mailto:postmaster@michaelbrusegard.com; ruf=mailto:postmaster@michaelbrusegard.com; adkim=s; aspf=s; fo=1"
  #   }
  #   mta_sts_policy = {
  #     name    = "_mta-sts"
  #     type    = "TXT"
  #     content = "v=STSv1; id=${var.mta_sts_id}"
  #   }
  # }
}

resource "cloudflare_dns_record" "safe" {
  for_each = local.safe_records

  zone_id  = local.zone_id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  ttl      = 300
  proxied  = false
  priority = try(each.value.priority, null)
}

# resource "cloudflare_dns_record" "mail" {
#   for_each = local.mail_records
#
#   zone_id  = local.zone_id
#   name     = each.value.name
#   type     = each.value.type
#   content  = each.value.content
#   ttl      = 300
#   proxied  = false
#   priority = try(each.value.priority, null)
# }
