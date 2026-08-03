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

variable "honcho_db_password" {
  description = "Honcho database password retained during staged retirement"
  type        = string
  sensitive   = true
}
