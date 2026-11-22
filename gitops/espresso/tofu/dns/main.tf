data "cloudflare_zone" "michaelbrusegard" {
  filter = {
    name = "michaelbrusegard.com"
  }
}

locals {
  # Public halves of the DKIM keys that infra-secrets mounts into Stalwart.
  # They are published in DNS anyway, so they live here rather than in sops.
  dkim_public_keys = {
    michaelbrusegard = {
      rsa     = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2XqUGly6/4WCR7kSqO8Ecz17udneH95OY9/0xBoE8Nf4Su3t1Er98cIYVx0Icc/XoP81jmcpcUt9yT6DHezMp552zWsnT+Z73o0uwB0melWnSdz3428Bjx1i1cweb+vX2HmbadLmD0sX1fGZPIOmDvjPlziWToS7HIYBNiqi8MkkYA9mrUpT5+23fONTM3tQHacuMORHXVWGujy5xiX6HWlOORmq2BBQgR5gMgiGjuVyYPp8yd8mLY+dyaLFRS0yUUwGa5eyqUJKD+FJNv8kw6S25CVALQQe68URk7dTFjqdKxGlQ8F8CqWIyBnNM0jIw6ypcOIXw73EX2CasHXZxQIDAQAB"
      ed25519 = "H2ogOU+rcoiRuOZlrhpCzSeHVKl3iYlj8MsDDgrCXog="
    }
    michbrus = {
      rsa     = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqRPaH23Ni+RJ/KGg14InxDs9MiEljQnM7ZFfVlv4XGekQN0cwgGDM7zVbL388os4x+b9vxcIBZoiKDFE13Py1wuKAAHZWk814yY+qcNDAwKcFRjTVNwAKAWv9QCKsV+3ikMzYYAhJ6o3tanbeCoc3jqO1lrkzfi/ThnyiucRjlnyoMTMTlu+sYlZ2unIq80uVAUZseU0VL5yRmBWbmUpiBwv6C2roPpZKaJnYntIvJs2V6B2LUcAwCdwDFCDD1felb9+KRdReG/cin9GtNZ8eFMbfPXEb5iNJzYxxNYf5sJAtbAHc644iwiSbu5psWR3kzpPbBAOFaL7WrblkMAxkwIDAQAB"
      ed25519 = "WWzdBNBby9rhpW8wDep9+gczoualmAyAeOJpOxV9wTQ="
    }
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
      content = "v=DKIM1; k=rsa; p=${local.dkim_public_keys.michaelbrusegard.rsa}"
    }
    dkim_ed25519 = {
      name    = "stalwart-ed25519._domainkey"
      type    = "TXT"
      content = "v=DKIM1; k=ed25519; p=${local.dkim_public_keys.michaelbrusegard.ed25519}"
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
      content = "v=DKIM1; k=rsa; p=${local.dkim_public_keys.michbrus.rsa}"
    }
    dkim_ed25519 = {
      name    = "stalwart-ed25519._domainkey"
      type    = "TXT"
      content = "v=DKIM1; k=ed25519; p=${local.dkim_public_keys.michbrus.ed25519}"
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
