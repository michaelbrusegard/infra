variable "pg_admin_user" {
  description = "Shared Postgres admin user"
  type        = string
  sensitive   = true
}

variable "pg_admin_password" {
  description = "Shared Postgres admin password"
  type        = string
  sensitive   = true
}

variable "nextcloud_db_password" {
  description = "Personal Nextcloud application role password"
  type        = string
  sensitive   = true
}

variable "immich_db_password" {
  description = "Immich application role password"
  type        = string
  sensitive   = true
}
