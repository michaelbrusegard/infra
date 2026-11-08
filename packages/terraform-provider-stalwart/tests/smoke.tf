terraform {
  required_providers {
    stalwart = {
      source  = "michaelbrusegard/stalwart"
      version = "1.0.3"
    }
  }
}

provider "stalwart" {}

variable "issuer_url" { type = string }
variable "directory_id" { type = string }
variable "application_id" { type = string }
variable "relay_id" { type = string }

# These types have no unique key, so creation would duplicate the objects.
import {
  to = stalwart_directory_oidc.pocket_id
  id = var.directory_id
}
import {
  to = stalwart_application.webui
  id = var.application_id
}
# Import also preserves an existing relay secret that is absent from config.
import {
  to = stalwart_mta_route_relay.mx
  id = var.relay_id
}

resource "stalwart_http" "server" {
  client_ip_source    = "xForwardedFor"
  forwarded_hops      = 1
  use_permissive_cors = false
  redirect_root       = "/account"
  response_headers = {
    "X-Provider-Smoke" = "applied"
  }
}

resource "stalwart_security" "server" {
  auth_ban_period = 3600000
}

resource "stalwart_system_settings" "server" {
  default_hostname  = "mail.manafishrov.test"
  default_domain_id = stalwart_domain.mail.id
  max_connections   = 8192
  include_secrets   = false
}

resource "stalwart_authentication" "server" {
  directory_id          = stalwart_directory_oidc.pocket_id.id
  min_password_length   = 8
  max_password_length   = 128
  min_password_strength = "three"
}

resource "stalwart_imap" "server" {
  allow_plain_text_auth      = false
  max_concurrent_connections = 16
  anonymous_timeout          = 60000
  authenticated_timeout      = 1800000
  idle_timeout               = 1800000
  rate_limit = {
    count  = 2000
    period = 60000
  }
}

resource "stalwart_domain" "mail" {
  name        = "manafishrov.test"
  description = "managed by provider smoke"
  enable      = true
  dkim_management = {
    type = "Manual"
  }
}

resource "stalwart_network_listener" "edge" {
  name         = "provider-smoke"
  bind         = ["127.0.0.1:12526"]
  protocol     = "smtp"
  use_tls      = false
  implicit_tls = false
}

resource "stalwart_directory_oidc" "pocket_id" {
  description        = "managed by provider smoke"
  issuer_url         = var.issuer_url
  claim_username     = "email"
  claim_name         = "name"
  claim_groups       = "groups"
  accepted_audiences = ["stalwart"]
  username_domain    = "manafishrov.test"
  unscoped_tokens    = "interoperable"
}

resource "stalwart_application" "webui" {
  description          = "managed by provider smoke"
  resource_url         = "https://example.com/provider-smoke.zip"
  url_prefix           = ["/provider-smoke"]
  enable               = false
  auto_update_interval = 2592000000
}

resource "stalwart_mta_route_relay" "mx" {
  name        = "provider-smoke"
  host        = "smtp.example.com"
  description = "managed by provider smoke"
  auth_secret = {
    type = "Value"
  }
}
