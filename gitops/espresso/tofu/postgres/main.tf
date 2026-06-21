resource "postgresql_role" "nextcloud" {
  name                = "nextcloud_app"
  login               = true
  password_wo         = var.nextcloud_db_password
  password_wo_version = 1
}

resource "postgresql_database" "nextcloud" {
  name  = "nextcloud"
  owner = postgresql_role.nextcloud.name
}

resource "postgresql_grant" "nextcloud_revoke_public_database_access" {
  database    = postgresql_database.nextcloud.name
  role        = "public"
  object_type = "database"
  privileges  = []
}

resource "postgresql_grant" "nextcloud_connect" {
  database    = postgresql_database.nextcloud.name
  role        = postgresql_role.nextcloud.name
  object_type = "database"
  privileges  = ["CONNECT", "CREATE", "TEMPORARY"]
}

resource "postgresql_role" "immich" {
  name                = "immich_app"
  login               = true
  password_wo         = var.immich_db_password
  password_wo_version = 1
}

resource "postgresql_database" "immich" {
  name  = "immich"
  owner = postgresql_role.immich.name
}

resource "postgresql_grant" "immich_revoke_public_database_access" {
  database    = postgresql_database.immich.name
  role        = "public"
  object_type = "database"
  privileges  = []
}

resource "postgresql_grant" "immich_connect" {
  database    = postgresql_database.immich.name
  role        = postgresql_role.immich.name
  object_type = "database"
  privileges  = ["CONNECT", "CREATE", "TEMPORARY"]
}

resource "postgresql_extension" "immich_vector" {
  name     = "vector"
  database = postgresql_database.immich.name

  depends_on = [postgresql_grant.immich_connect]
}

resource "postgresql_extension" "immich_vchord" {
  name     = "vchord"
  database = postgresql_database.immich.name

  depends_on = [postgresql_extension.immich_vector]
}

resource "postgresql_extension" "immich_cube" {
  name     = "cube"
  database = postgresql_database.immich.name

  depends_on = [postgresql_extension.immich_vchord]
}

resource "postgresql_extension" "immich_earthdistance" {
  name     = "earthdistance"
  database = postgresql_database.immich.name

  depends_on = [postgresql_extension.immich_cube]
}
