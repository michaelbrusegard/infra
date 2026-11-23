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
    opencloud_role = "opencloudAdmin"
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

resource "pocketid_client" "healthlog" {
  name = "HealthLog"

  callback_urls = [
    "https://health.${local.domain}/api/auth/oidc/callback",
  ]

  launch_url = "https://health.${local.domain}"

  allowed_user_groups = [
    pocketid_group.admin.id,
  ]
}

# OpenCloud reads the role from opencloud_role. Keep users out of both
# groups: Pocket ID merges their claims, so one would win at random.
resource "pocketid_group" "opencloud" {
  name          = "opencloud"
  friendly_name = "OpenCloud Users"
  custom_claims = {
    opencloud_role = "opencloudUser"
  }
}

# The apps use fixed public client IDs, so each gets a client with that ID.
# The web client's ID is set to match WEB_OIDC_CLIENT_ID.
locals {
  opencloud_clients = {
    web = {
      name      = "OpenCloud"
      client_id = "OpenCloudWeb"
      callback_urls = [
        "https://cloud.${local.domain}/",
        "https://cloud.${local.domain}/oidc-callback.html",
        "https://cloud.${local.domain}/oidc-silent-redirect.html",
      ]
      logout_callback_urls = ["https://cloud.${local.domain}"]
      launch_url           = "https://cloud.${local.domain}"
    }
    desktop = {
      name                 = "OpenCloud Desktop"
      client_id            = "OpenCloudDesktop"
      callback_urls        = ["http://127.0.0.1", "http://localhost"]
      logout_callback_urls = null
      launch_url           = null
    }
    android = {
      name                 = "OpenCloud Android"
      client_id            = "OpenCloudAndroid"
      callback_urls        = ["oc://android.opencloud.eu"]
      logout_callback_urls = null
      launch_url           = null
    }
    ios = {
      name                 = "OpenCloud iOS"
      client_id            = "OpenCloudIOS"
      callback_urls        = ["oc://ios.opencloud.eu"]
      logout_callback_urls = null
      launch_url           = null
    }
  }
}

resource "pocketid_client" "opencloud" {
  for_each = local.opencloud_clients

  name                 = each.value.name
  client_id            = each.value.client_id
  callback_urls        = each.value.callback_urls
  logout_callback_urls = each.value.logout_callback_urls
  launch_url           = each.value.launch_url
  is_public            = true
  pkce_enabled         = true

  allowed_user_groups = sort([
    pocketid_group.opencloud.id,
    pocketid_group.admin.id,
  ])
}
