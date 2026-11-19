data "cloudflare_zone" "michaelbrusegard" {
  filter = {
    name = "michaelbrusegard.com"
  }
}

locals {
  dns_records = merge({
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
  }, local.stalwart_mail.michaelbrusegard)
}

# Cloudflare only accepts automatic TTL (1) on proxied records.
resource "cloudflare_dns_record" "safe" {
  for_each = local.dns_records

  zone_id  = data.cloudflare_zone.michaelbrusegard.zone_id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  ttl      = try(each.value.ttl, try(each.value.proxied, false) ? 1 : 300)
  proxied  = try(each.value.proxied, false)
  priority = try(each.value.priority, null)
}

data "cloudflare_zone" "michbrus" {
  filter = {
    name = "michbrus.com"
  }
}

locals {
  michbrus_records = merge({
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
  }, local.stalwart_mail.michbrus)
}

resource "cloudflare_dns_record" "michbrus" {
  for_each = local.michbrus_records

  zone_id  = data.cloudflare_zone.michbrus.zone_id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  ttl      = try(each.value.ttl, 300)
  proxied  = false
  priority = try(each.value.priority, null)
}
