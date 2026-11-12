# Pocket ID provisions the mailbox account over SCIM; this stack never creates
# accounts. DNS records, including DKIM, belong to the dns stack.
resource "stalwart_domain" "michaelbrusegard" {
  name                    = "michaelbrusegard.com"
  enable                  = true
  allow_relaying          = false
  allow_scim_provisioning = true
  # Role addresses (postmaster@, infra@, mb@, ...) land in the one mailbox, and
  # the patched server lets the mailbox send as any address nobody else owns.
  catch_all_address = "michaelbrusegard@michaelbrusegard.com"
  certificate_management = {
    type = "Manual"
  }
  dkim_management = {
    type = "Manual"
  }
  dns_management = {
    type = "Manual"
  }
  report_address_uri = "mailto:postmaster@michaelbrusegard.com"
  sub_addressing = {
    custom_rule = null
    type        = "Enabled"
  }
}

# Per-service addresses (github@, bank@, ...) all land in the one mailbox.
resource "stalwart_domain" "michbrus" {
  name                    = "michbrus.com"
  enable                  = true
  allow_relaying          = false
  allow_scim_provisioning = true
  catch_all_address       = "michaelbrusegard@michaelbrusegard.com"
  certificate_management = {
    type = "Manual"
  }
  dkim_management = {
    type = "Manual"
  }
  dns_management = {
    type = "Manual"
  }
  report_address_uri = "mailto:postmaster@michaelbrusegard.com"
}

locals {
  dkim_domains = {
    "michaelbrusegard.com" = stalwart_domain.michaelbrusegard.id
    "michbrus.com"         = stalwart_domain.michbrus.id
  }
}

resource "stalwart_dkim_signature_dkim1_rsa_sha256" "this" {
  for_each = local.dkim_domains

  domain_id = each.value
  selector  = "stalwart-rsa"
  private_key = {
    type      = "File"
    file_path = "/var/lib/stalwart/private/dkim/${each.key}.rsa.key"
  }
}

resource "stalwart_dkim_signature_dkim1_ed25519_sha256" "this" {
  for_each = local.dkim_domains

  domain_id = each.value
  selector  = "stalwart-ed25519"
  private_key = {
    type      = "File"
    file_path = "/var/lib/stalwart/private/dkim/${each.key}.ed25519.key"
  }
}
