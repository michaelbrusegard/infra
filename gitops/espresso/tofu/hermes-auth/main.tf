locals {
  domain = "asgard.michaelbrusegard.com"
}

data "pocketid_group" "admin" {
  name = "admin"
}

resource "pocketid_client" "android_viewer" {
  name = "Hermes Android Viewer"

  callback_urls = [
    "https://android.${local.domain}/oauth2/callback",
  ]

  logout_callback_urls = [
    "https://android.${local.domain}/",
  ]

  launch_url   = "https://android.${local.domain}/vnc.html?autoconnect=true&resize=scale&view_only=false&reconnect=true"
  pkce_enabled = true

  allowed_user_groups = [
    data.pocketid_group.admin.id,
  ]
}

resource "random_password" "oauth2_cookie_secret" {
  length           = 32
  special          = true
  override_special = "-_"
}
