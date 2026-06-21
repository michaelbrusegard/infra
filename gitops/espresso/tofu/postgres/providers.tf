provider "postgresql" {
  host      = "postgres.postgres.svc.cluster.local"
  port      = 5432
  database  = "postgres"
  username  = var.pg_admin_user
  password  = var.pg_admin_password
  sslmode   = "disable"
  superuser = true
}
