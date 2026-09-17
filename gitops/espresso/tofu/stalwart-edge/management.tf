resource "stalwart_domain" "internal" {
  name                   = "system.edge.asgard.michaelbrusegard.com"
  description            = "Internal bootstrap machine identities only; never an SMTP destination"
  is_enabled             = false
  allow_relaying         = false
  aliases                = []
  directory_id           = null
  catch_all_address      = null
  certificate_management = { type = "Manual" }
  dkim_management        = { type = "Manual" }
  dns_management         = { type = "Manual" }
  sub_addressing         = { type = "Disabled" }

  lifecycle {
    prevent_destroy = true
    postcondition {
      condition     = self.directory_id == null && self.catch_all_address == null
      error_message = "Bootstrap internal domain must have no directory or catch-all."
    }
  }
}

resource "stalwart_certificate" "wildcard" {
  certificate = {
    type      = "File"
    file_path = "/var/lib/stalwart/private/tls/tls.crt"
  }
  private_key = {
    type      = "File"
    file_path = "/var/lib/stalwart/private/tls/tls.key"
  }
  lifecycle { prevent_destroy = true }
}

resource "stalwart_system_settings" "edge" {
  default_hostname       = "mail.asgard.michaelbrusegard.com"
  default_domain_id      = stalwart_domain.internal.id
  default_certificate_id = stalwart_certificate.wildcard.id
  proxy_trusted_networks = []
}

resource "stalwart_network_listener" "https" {
  name                            = "https"
  protocol                        = "http"
  bind                            = ["[::]:443"]
  use_tls                         = true
  tls_implicit                    = true
  override_proxy_trusted_networks = []
  lifecycle { prevent_destroy = true }
}

resource "stalwart_http" "management" {
  use_x_forwarded     = false
  use_permissive_cors = false
  enable_hsts         = true
}

resource "stalwart_application" "webui" {
  description           = "Stalwart Web Interface (disabled on headless edge)"
  enabled               = false
  resource_url          = var.webui_resource_url
  url_prefix            = ["/admin", "/account"]
  auto_update_frequency = 2592000000
}

# No external/global Directory. The machine User, its Replace permissions and
# API key remain bootstrap-owned, outside this provider's account mapping.
resource "stalwart_authentication" "edge" {
  directory_id            = null
  default_admin_role_ids  = []
  default_user_role_ids   = []
  default_group_role_ids  = []
  default_tenant_role_ids = []
  lifecycle {
    postcondition {
      condition     = self.directory_id == null
      error_message = "A global authentication directory is forbidden on the edge."
    }
  }
}

import {
  to = stalwart_domain.internal
  id = var.bootstrap_internal_domain_id
}
import {
  to = stalwart_certificate.wildcard
  id = var.bootstrap_certificate_id
}
import {
  to = stalwart_network_listener.https
  id = var.bootstrap_https_listener_id
}
import {
  for_each = var.bootstrap_webui_id == null ? {} : { webui = var.bootstrap_webui_id }
  to       = stalwart_application.webui
  id       = each.value
}
