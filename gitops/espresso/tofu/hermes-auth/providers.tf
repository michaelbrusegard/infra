provider "pocketid" {
  base_url  = "https://id.${local.domain}"
  api_token = var.pocket_id_api_token
}
