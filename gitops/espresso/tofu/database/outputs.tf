output "nextcloud_db_password" {
  value     = var.nextcloud_db_password
  sensitive = true
}

output "immich_db_password" {
  value     = var.immich_db_password
  sensitive = true
}
