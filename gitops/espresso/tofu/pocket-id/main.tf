locals {
  domain = "gullhaugveien.michaelbrusegard.com"
}

resource "pocketid_group" "users" {
  name          = "Users"
  friendly_name = "NetBird Users"
}

resource "pocketid_client" "netbird" {
  name = "NetBird"

  callback_urls = [
    "https://netbird-admin.${local.domain}/#callback",
    "https://netbird-admin.${local.domain}/#silent-callback",
    "http://localhost:53000/",
  ]

  is_public    = true
  pkce_enabled = true
  launch_url   = "https://netbird-admin.${local.domain}/"

  allowed_user_groups = [pocketid_group.users.id]
}
