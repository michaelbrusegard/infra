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

variable "hindsight_db_password" {
  description = "Hindsight application role password"
  type        = string
  sensitive   = true
}

variable "mattermost_db_password" {
  description = "Mattermost application role password"
  type        = string
  sensitive   = true
}

variable "mealie_db_password" {
  description = "Mealie application role password"
  type        = string
  sensitive   = true
}
