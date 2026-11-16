# Both zones were signed by hand in Cloudflare and imported; this keeps
# DNSSEC declared.
# Cloudflare registers the domains, so it publishes the DS records itself.
resource "cloudflare_zone_dnssec" "michaelbrusegard" {
  zone_id = data.cloudflare_zone.michaelbrusegard.zone_id
  status  = "active"
}

resource "cloudflare_zone_dnssec" "michbrus" {
  zone_id = data.cloudflare_zone.michbrus.zone_id
  status  = "active"
}
