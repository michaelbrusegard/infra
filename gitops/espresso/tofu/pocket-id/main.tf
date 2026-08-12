locals {
  domain = "asgard.michaelbrusegard.com"
}

resource "pocketid_group" "users" {
  name          = "Users"
  friendly_name = "NetBird Users"
  custom_claims = {
    netbird_groups = jsonencode(["Users"])
  }
}

resource "pocketid_group" "admin" {
  name          = "admin"
  friendly_name = "Admin Users"
  custom_claims = {
    netbird_groups = jsonencode(["Users", "Admins", "Personal Devices"])
  }
}

resource "pocketid_client" "netbird" {
  name = "NetBird"

  callback_urls = [
    "https://netbird-admin.${local.domain}/auth",
    "https://netbird-admin.${local.domain}/silent-auth",
    "http://localhost:53000/",
  ]

  is_public    = true
  pkce_enabled = true
  launch_url   = "https://netbird-admin.${local.domain}/"

  allowed_user_groups = sort([
    pocketid_group.users.id,
    pocketid_group.admin.id,
  ])
}

resource "pocketid_group" "nextcloud" {
  name          = "nextcloud"
  friendly_name = "Nextcloud Users"
}

resource "pocketid_client" "nextcloud" {
  name = "Nextcloud"

  callback_urls = [
    "https://cloud.${local.domain}/apps/user_oidc/code",
  ]

  launch_url   = "https://cloud.${local.domain}"
  pkce_enabled = true

  allowed_user_groups = sort([
    pocketid_group.nextcloud.id,
    pocketid_group.admin.id,
  ])
}

resource "pocketid_group" "immich" {
  name          = "immich"
  friendly_name = "Immich Users"
}

resource "pocketid_client" "immich" {
  name = "Immich"

  callback_urls = [
    "https://photos.${local.domain}/auth/login",
    "https://photos.${local.domain}/user-settings",
    "https://photos.${local.domain}/api/oauth/mobile-redirect",
  ]

  launch_url   = "https://photos.${local.domain}"
  pkce_enabled = true

  allowed_user_groups = sort([
    pocketid_group.immich.id,
    pocketid_group.admin.id,
  ])
}

resource "pocketid_client" "mealie" {
  name = "Mealie"

  callback_urls = [
    "https://mealie.${local.domain}/login",
    "https://mealie.${local.domain}/login?direct=1",
  ]

  is_public    = false
  pkce_enabled = true
  launch_url   = "https://mealie.${local.domain}"

  allowed_user_groups = sort([
    pocketid_group.users.id,
    pocketid_group.admin.id,
  ])
}
