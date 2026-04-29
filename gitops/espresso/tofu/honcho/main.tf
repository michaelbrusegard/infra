resource "postgresql_role" "honcho" {
  name                = "honcho_app"
  login               = true
  password_wo         = var.honcho_db_password
  password_wo_version = "1"
}

resource "postgresql_database" "honcho" {
  name  = "honcho"
  owner = postgresql_role.honcho.name
}

resource "postgresql_grant" "honcho_revoke_public_database_access" {
  database    = postgresql_database.honcho.name
  role        = "public"
  object_type = "database"
  privileges  = []
}

resource "postgresql_grant" "honcho_connect" {
  database    = postgresql_database.honcho.name
  role        = postgresql_role.honcho.name
  object_type = "database"
  privileges  = ["CONNECT", "CREATE", "TEMPORARY"]
}

resource "postgresql_extension" "vector" {
  name     = "vector"
  database = postgresql_database.honcho.name

  depends_on = [postgresql_grant.honcho_connect]
}
