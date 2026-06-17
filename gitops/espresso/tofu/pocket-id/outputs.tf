output "nextcloud_pocketid_client_id" {
  value = pocketid_client.nextcloud.id
}

output "nextcloud_pocketid_client_secret" {
  value     = pocketid_client.nextcloud.client_secret
  sensitive = true
}

output "immich_pocketid_client_id" {
  value = pocketid_client.immich.id
}

output "immich_pocketid_client_secret" {
  value     = pocketid_client.immich.client_secret
  sensitive = true
}

output "immich_config_json" {
  value = jsonencode({
    machineLearning = {
      urls = ["http://machine-learning:3003"]
    }
    oauth = {
      autoLaunch              = false
      autoRegister            = true
      buttonText              = "Sign in with Pocket ID"
      clientId                = pocketid_client.immich.id
      clientSecret            = pocketid_client.immich.client_secret
      enabled                 = true
      issuerUrl               = "https://id.asgard.michaelbrusegard.com"
      mobileOverrideEnabled   = true
      mobileRedirectUri       = "https://photos.asgard.michaelbrusegard.com/api/oauth/mobile-redirect"
      scope                   = "openid email profile"
      storageLabelClaim       = "preferred_username"
      tokenEndpointAuthMethod = "client_secret_post"
    }
    server = {
      externalDomain = "https://photos.asgard.michaelbrusegard.com"
    }
  })
  sensitive = true
}
