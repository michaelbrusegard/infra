locals {
  domain = "asgard.michaelbrusegard.com"

  resources = {
    bazarr = {
      name    = "Bazarr"
      address = "bazarr.${local.domain}"
      group   = "media_admin"
    }
    cloud = {
      name    = "Nextcloud"
      address = "cloud.${local.domain}"
      group   = "public"
    }
    cubeman = {
      name    = "Cubeman"
      address = "10.0.189.21/32"
      group   = "home"
    }
    feishin = {
      name    = "Feishin"
      address = "feishin.${local.domain}"
      group   = "media"
    }
    grafana = {
      name    = "Grafana"
      address = "grafana.${local.domain}"
      group   = "infra"
    }
    hermes_agent = {
      name    = "Hermes Agent"
      address = "hermes.${local.domain}"
      group   = "infra"
    }
    homebridge = {
      name    = "Homebridge"
      address = "homebridge.${local.domain}"
      group   = "home"
    }
    hubble = {
      name    = "Hubble UI"
      address = "hubble.${local.domain}"
      group   = "infra"
    }
    jellyfin = {
      name    = "Jellyfin"
      address = "jellyfin.${local.domain}"
      group   = "media"
    }
    musicgrabber = {
      name    = "MusicGrabber"
      address = "musicgrabber.${local.domain}"
      group   = "media_admin"
    }
    navidrome = {
      name    = "Navidrome"
      address = "navidrome.${local.domain}"
      group   = "media"
    }
    netbird_admin = {
      name    = "NetBird Admin"
      address = "netbird-admin.${local.domain}"
      group   = "infra"
    }
    prowlarr = {
      name    = "Prowlarr"
      address = "prowlarr.${local.domain}"
      group   = "media_admin"
    }
    radarr = {
      name    = "Radarr"
      address = "radarr.${local.domain}"
      group   = "media_admin"
    }
    rustfs = {
      name    = "RustFS"
      address = "rustfs.${local.domain}"
      group   = "infra"
    }
    rustfs_s3 = {
      name    = "Manafish S3"
      address = "s3.manafishrov.com"
      group   = "manafish"
    }
    seerr = {
      name    = "Seerr"
      address = "seerr.${local.domain}"
      group   = "media"
    }
    sonarr = {
      name    = "Sonarr"
      address = "sonarr.${local.domain}"
      group   = "media_admin"
    }
    stalwart = {
      name    = "Stalwart"
      address = "mail.${local.domain}"
      group   = "infra"
    }
    transmission = {
      name    = "Transmission"
      address = "transmission.${local.domain}"
      group   = "media_admin"
    }
    unifi = {
      name    = "Unifi"
      address = "unifi.${local.domain}"
      group   = "infra"
    }
    uptime = {
      name    = "Uptime Kuma"
      address = "uptime.${local.domain}"
      group   = "infra"
    }
    zigbee2mqtt = {
      name    = "zigbee2mqtt"
      address = "zigbee.${local.domain}"
      group   = "home"
    }
    pgweb = {
      name    = "Pgweb"
      address = "pgweb.${local.domain}"
      group   = "infra"
    }
    photos = {
      name    = "Immich"
      address = "photos.${local.domain}"
      group   = "public"
    }
    pocket_id = {
      name    = "Pocket ID"
      address = "id.${local.domain}"
      group   = "public"
    }
    status = {
      name    = "Status"
      address = "status.${local.domain}"
      group   = "public"
    }
  }
}

resource "netbird_group" "admins" {
  name = "Admins"
}

resource "netbird_group" "personal_devices" {
  name = "Personal Devices"
}

resource "netbird_group" "users" {
  name = "Users"
}

resource "netbird_group" "routing_peers" {
  name = "Routing Peers"
}

resource "netbird_group" "home" {
  name = "Home"
}

resource "netbird_group" "infra" {
  name = "Infra"
}

resource "netbird_group" "media" {
  name = "Media"
}

resource "netbird_group" "media_admin" {
  name = "Media Admin"
}

resource "netbird_group" "public" {
  name = "Public"
}

resource "netbird_group" "manafish" {
  name = "Manafish"
}

resource "netbird_setup_key" "macchiato" {
  name                   = "macchiato"
  type                   = "reusable"
  usage_limit            = 0
  allow_extra_dns_labels = true
  auto_groups            = [netbird_group.routing_peers.id]
  ephemeral              = false
  revoked                = false
}

resource "netbird_network" "asgard" {
  name        = "Asgard"
  description = "Routed internal services at Asgard"
}

resource "netbird_network_router" "macchiato" {
  network_id  = netbird_network.asgard.id
  peer_groups = [netbird_group.routing_peers.id]
  enabled     = true
  masquerade  = true
  metric      = 100
}

resource "netbird_network_resource" "resources" {
  for_each = local.resources

  network_id  = netbird_network.asgard.id
  name        = each.value.name
  description = "${each.value.name} at Asgard"
  address     = each.value.address
  groups = [
    each.value.group == "home" ? netbird_group.home.id : each.value.group == "infra" ? netbird_group.infra.id : each.value.group == "media" ? netbird_group.media.id : each.value.group == "public" ? netbird_group.public.id : each.value.group == "manafish" ? netbird_group.manafish.id : netbird_group.media_admin.id,
  ]
  enabled = true
}

resource "netbird_policy" "media_admin_access" {
  name        = "Media Admin Access"
  description = "Allow admins to access media admin resources"
  enabled     = true

  rule {
    name          = "Admins to media admin"
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "all"
    sources       = [netbird_group.admins.id]
    destinations  = [netbird_group.media_admin.id]
  }
}

resource "netbird_policy" "media_access" {
  name        = "Media Access"
  description = "Allow users to access media resources"
  enabled     = true

  rule {
    name          = "Users to media"
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "all"
    sources       = [netbird_group.users.id]
    destinations  = [netbird_group.media.id]
  }
}

resource "netbird_account_settings" "main" {
  user_approval_required              = false
  groups_propagation_enabled          = true
  jwt_groups_enabled                  = true
  jwt_groups_claim_name               = "netbird_groups"
  jwt_allow_groups                    = ["Users", "Admins", "Personal Devices"]
  routing_peer_dns_resolution_enabled = true
  peer_login_expiration_enabled       = true
  peer_login_expiration               = 604800
  peer_inactivity_expiration_enabled  = true
  peer_inactivity_expiration          = 604800
}

resource "netbird_policy" "infra_access" {
  name        = "Infra Access"
  description = "Allow admins to access infra resources"
  enabled     = true

  rule {
    name          = "Admins to infra"
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "all"
    sources       = [netbird_group.admins.id]
    destinations  = [netbird_group.infra.id]
  }
}

resource "netbird_policy" "public_access" {
  name        = "Public Access"
  description = "Allow users to access public resources"
  enabled     = true

  rule {
    name          = "Users to public"
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "all"
    sources       = [netbird_group.users.id]
    destinations  = [netbird_group.public.id]
  }
}

resource "netbird_policy" "manafish_access" {
  name        = "Manafish Access"
  description = "Allow admins to access Manafish resources"
  enabled     = true

  rule {
    name          = "Admins to Manafish"
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "all"
    sources       = [netbird_group.admins.id]
    destinations  = [netbird_group.manafish.id]
  }
}

resource "netbird_policy" "home_access" {
  name        = "Home Access"
  description = "Allow admins to access home resources"
  enabled     = true

  rule {
    name          = "Admins to home"
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "all"
    sources       = [netbird_group.admins.id]
    destinations  = [netbird_group.home.id]
  }
}

resource "netbird_policy" "personal_device_mesh" {
  name        = "Personal Device Mesh"
  description = "Allow personal admin devices to communicate with each other over NetBird"
  enabled     = true

  rule {
    name          = "Personal devices full mesh"
    action        = "accept"
    bidirectional = true
    enabled       = true
    protocol      = "all"
    sources       = [netbird_group.personal_devices.id]
    destinations  = [netbird_group.personal_devices.id]
  }
}

resource "netbird_nameserver_group" "router_public_dns" {
  name        = "Router Public DNS"
  description = "Public DNS for router domain to bypass hairpin routing through NetBird tunnel"
  enabled     = true
  primary     = false
  domains     = ["router.${local.domain}"]
  groups      = [netbird_group.admins.id, netbird_group.users.id]

  nameservers = [
    {
      ip      = "1.1.1.1"
      ns_type = "udp"
      port    = 53
    }
  ]

  search_domains_enabled = false
}

resource "netbird_nameserver_group" "macchiato_blocky_dns" {
  name        = "Macchiato Blocky DNS"
  description = "Blocky DNS on macchiato for Asgard domain"
  enabled     = true
  primary     = false
  domains     = [local.domain]
  groups      = [netbird_group.admins.id, netbird_group.users.id]

  nameservers = [
    {
      ip      = var.macchiato_blocky_dns_ip
      ns_type = "udp"
      port    = 53
    }
  ]

  search_domains_enabled = true
}
