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

# Imports for the manually-created objects. After the first successful apply
# these blocks can stay (they are no-ops once state matches) or be removed.
import {
  to = pocketid_group.users
  id = "bae4aed3-11e2-4130-9fd0-bc807313da68"
}

import {
  to = pocketid_client.netbird
  id = "a21f6c77-3db2-493f-92ad-abb86c0bcaaf"
}
