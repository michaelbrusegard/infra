data "cloudflare_zone" "michaelbrusegard" {
  filter = {
    name = "michaelbrusegard.com"
  }
}

locals {
  dns_records = {
    # external-dns owns the asgard CNAMEs, but midgard has no cluster to run
    # it, so cortado's relay name is a static CNAME onto the dyndns record
    # that already tracks that site's WAN address.
    netbird_midgard = {
      name    = "netbird.midgard"
      type    = "CNAME"
      content = "router.midgard.michaelbrusegard.com"
    }
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
    # external-dns can't own the apex: its TXT ownership record
    # (_externaldns.cname-michaelbrusegard.com) would fall outside the zone.
    # Cloudflare flattens the CNAME, so it can sit next to the apex MX and
    # TXT records. The gateway redirects it to old.michaelbrusegard.com.
    apex = {
      name    = "michaelbrusegard.com"
      type    = "CNAME"
      content = "router.asgard.michaelbrusegard.com"
      proxied = true
    }
    # SMTP2GO outbound relay: bounce return path and DKIM. Its link-tracking
    # CNAME is deliberately absent because tracking stays disabled.
    smtp2go_return_path = {
      name    = "em1206132"
      type    = "CNAME"
      content = "return.smtp2go.net"
    }
    smtp2go_dkim = {
      name    = "s1206132._domainkey"
      type    = "CNAME"
      content = "dkim.smtp2go.net"
    }
    tlsrpt = {
      name    = "_smtp._tls"
      type    = "TXT"
      content = "v=TLSRPTv1; rua=mailto:postmaster@michaelbrusegard.com"
    }
    # mta_sts = {
    #   name    = "mta-sts"
    #   type    = "CNAME"
    #   content = "mail.asgard.michaelbrusegard.com"
    # }
    # autoconfig = {
    #   name    = "autoconfig"
    #   type    = "CNAME"
    #   content = "mail.asgard.michaelbrusegard.com"
    # }
    # autodiscover = {
    #   name    = "autodiscover"
    #   type    = "CNAME"
    #   content = "mail.asgard.michaelbrusegard.com"
    # }
    # mx = {
    #   name     = "@"
    #   type     = "MX"
    #   content  = "mail.asgard.michaelbrusegard.com"
    #   priority = 10
    # }
    # spf = {
    #   name    = "@"
    #   type    = "TXT"
    #   content = "v=spf1 mx -all"
    # }
    # dmarc = {
    #   name    = "_dmarc"
    #   type    = "TXT"
    #   content = "v=DMARC1; p=quarantine; rua=mailto:postmaster@michaelbrusegard.com; ruf=mailto:postmaster@michaelbrusegard.com; adkim=s; aspf=s; fo=1"
    # }
    # mta_sts_policy = {
    #   name    = "_mta-sts"
    #   type    = "TXT"
    #   content = "v=STSv1; id=${var.mta_sts_id}"
    # }
  }
}

# Cloudflare only accepts automatic TTL (1) on proxied records.
resource "cloudflare_dns_record" "safe" {
  for_each = local.dns_records

  zone_id  = data.cloudflare_zone.michaelbrusegard.zone_id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  ttl      = try(each.value.proxied, false) ? 1 : 300
  proxied  = try(each.value.proxied, false)
  priority = try(each.value.priority, null)
}

data "cloudflare_zone" "michbrus" {
  filter = {
    name = "michbrus.com"
  }
}

# Proton's existing MX, SPF, DKIM and DMARC records stay unmanaged until the
# mail cutover replaces them.
locals {
  michbrus_records = {
    # SMTP2GO outbound relay: bounce return path and DKIM. Its link-tracking
    # CNAME is deliberately absent because tracking stays disabled.
    smtp2go_return_path = {
      name    = "em1206132"
      type    = "CNAME"
      content = "return.smtp2go.net"
    }
    smtp2go_dkim = {
      name    = "s1206132._domainkey"
      type    = "CNAME"
      content = "dkim.smtp2go.net"
    }
    # Stalwart signs with these; the private keys live in infra-secrets.
    dkim_rsa = {
      name    = "stalwart-rsa._domainkey"
      type    = "TXT"
      content = "v=DKIM1; k=rsa; p=${var.dkim_rsa_pub_michbrus}"
    }
    dkim_ed25519 = {
      name    = "stalwart-ed25519._domainkey"
      type    = "TXT"
      content = "v=DKIM1; k=ed25519; p=${var.dkim_ed25519_pub_michbrus}"
    }
  }
}

resource "cloudflare_dns_record" "michbrus" {
  for_each = local.michbrus_records

  zone_id = data.cloudflare_zone.michbrus.zone_id
  name    = each.value.name
  type    = each.value.type
  content = each.value.content
  ttl     = 300
  proxied = false
}
