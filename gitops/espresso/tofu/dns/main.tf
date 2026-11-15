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
    # Proton's DKIM keys and domain verification stay while Proton can still
    # send as this domain; they do not route mail. Proton created them with
    # automatic TTL.
    proton_verification = {
      name    = "michaelbrusegard.com"
      type    = "TXT"
      content = "\"protonmail-verification=ede78d1c2406786df23d6874aae245da7c61b075\""
      ttl     = 1
    }
    proton_dkim = {
      name    = "protonmail._domainkey.michaelbrusegard.com"
      type    = "CNAME"
      content = "protonmail.domainkey.dxxn4pqwnzw6mzwwzvq6sha6443ciruhtismdampicgutgw6oe6xq.domains.proton.ch"
      ttl     = 1
    }
    proton_dkim2 = {
      name    = "protonmail2._domainkey.michaelbrusegard.com"
      type    = "CNAME"
      content = "protonmail2.domainkey.dxxn4pqwnzw6mzwwzvq6sha6443ciruhtismdampicgutgw6oe6xq.domains.proton.ch"
      ttl     = 1
    }
    proton_dkim3 = {
      name    = "protonmail3._domainkey.michaelbrusegard.com"
      type    = "CNAME"
      content = "protonmail3.domainkey.dxxn4pqwnzw6mzwwzvq6sha6443ciruhtismdampicgutgw6oe6xq.domains.proton.ch"
      ttl     = 1
    }
  }, var.mail_on_stalwart ? local.stalwart_mail.michaelbrusegard : local.proton_mail.michaelbrusegard)
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
    # Proton Pass alias DKIM and domain verification; see the note on the
    # michaelbrusegard.com equivalents.
    proton_verification = {
      name    = "michbrus.com"
      type    = "TXT"
      content = "\"pm-verification=upjbsplvugrbrpzczsfshlteddfkgd\""
      ttl     = 1
    }
    proton_dkim = {
      name    = "dkim._domainkey.michbrus.com"
      type    = "CNAME"
      content = "dkim._domainkey.alias.proton.me"
      ttl     = 1
    }
    proton_dkim02 = {
      name    = "dkim02._domainkey.michbrus.com"
      type    = "CNAME"
      content = "dkim02._domainkey.alias.proton.me"
      ttl     = 1
    }
    proton_dkim03 = {
      name    = "dkim03._domainkey.michbrus.com"
      type    = "CNAME"
      content = "dkim03._domainkey.alias.proton.me"
      ttl     = 1
    }
  }, var.mail_on_stalwart ? local.stalwart_mail.michbrus : local.proton_mail.michbrus)
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
