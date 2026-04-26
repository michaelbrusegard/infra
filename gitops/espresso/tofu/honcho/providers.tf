provider "postgresql" {
  host      = var.pg_host
  port      = var.pg_port
  database  = var.pg_database
  username  = var.pg_admin_user
  password  = var.pg_admin_password
  sslmode   = var.pg_sslmode
  superuser = var.pg_superuser
}
