data "cloudflare_zone" "michaelbrusegard" {
  filter = {
    name = "michaelbrusegard.com"
  }
}

locals {
  dns_records = {
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

resource "cloudflare_dns_record" "safe" {
  for_each = local.dns_records

  zone_id  = data.cloudflare_zone.michaelbrusegard.zone_id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  ttl      = 300
  proxied  = false
  priority = try(each.value.priority, null)
}
