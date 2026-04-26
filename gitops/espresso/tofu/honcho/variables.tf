variable "pg_host" {
  description = "Shared Postgres host"
  type        = string
  default     = "postgres.postgres.svc.cluster.local"
}

variable "pg_port" {
  description = "Shared Postgres port"
  type        = number
  default     = 5432
}

variable "pg_database" {
  description = "Admin database for provisioning"
  type        = string
  default     = "postgres"
}

variable "pg_sslmode" {
  description = "SSL mode for Postgres connections"
  type        = string
  default     = "disable"
}

variable "pg_superuser" {
  description = "Whether the provisioning user is a Postgres superuser"
  type        = bool
  default     = true
}

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

variable "honcho_db_name" {
  description = "Honcho database name"
  type        = string
  default     = "honcho"
}

variable "honcho_db_user" {
  description = "Honcho database user"
  type        = string
  default     = "honcho_app"
}

variable "honcho_db_password" {
  description = "Honcho database password"
  type        = string
  sensitive   = true
}

variable "honcho_db_password_version" {
  description = "Bump to rotate Honcho database password"
  type        = string
  default     = "1"
}
