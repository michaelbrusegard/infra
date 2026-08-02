output "nextcloud_db_password" {
  value     = var.nextcloud_db_password
  sensitive = true
}

output "immich_db_password" {
  value     = var.immich_db_password
  sensitive = true
}

output "hindsight_db_password" {
  value     = var.hindsight_db_password
  sensitive = true
}

output "mattermost_db_password" {
  value     = var.mattermost_db_password
  sensitive = true
}

output "mealie_db_password" {
  value     = var.mealie_db_password
  sensitive = true
}
