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

resource "postgresql_role" "hindsight" {
  name                = "hindsight_app"
  login               = true
  password_wo         = var.hindsight_db_password
  password_wo_version = 2
}

resource "postgresql_database" "hindsight" {
  name  = "hindsight"
  owner = postgresql_role.hindsight.name
}

resource "postgresql_grant" "hindsight_revoke_public_database_access" {
  database    = postgresql_database.hindsight.name
  role        = "public"
  object_type = "database"
  privileges  = []
}

resource "postgresql_grant" "hindsight_connect" {
  database    = postgresql_database.hindsight.name
  role        = postgresql_role.hindsight.name
  object_type = "database"
  privileges  = ["CONNECT", "CREATE", "TEMPORARY"]
}

resource "postgresql_extension" "hindsight_vector" {
  name     = "vector"
  database = postgresql_database.hindsight.name

  depends_on = [postgresql_grant.hindsight_connect]
}

resource "postgresql_role" "mattermost" {
  name                = "mattermost_app"
  login               = true
  password_wo         = var.mattermost_db_password
  password_wo_version = 2
}

resource "postgresql_database" "mattermost" {
  name  = "mattermost"
  owner = postgresql_role.mattermost.name
}

resource "postgresql_grant" "mattermost_revoke_public_database_access" {
  database    = postgresql_database.mattermost.name
  role        = "public"
  object_type = "database"
  privileges  = []
}

resource "postgresql_grant" "mattermost_connect" {
  database    = postgresql_database.mattermost.name
  role        = postgresql_role.mattermost.name
  object_type = "database"
  privileges  = ["CONNECT", "CREATE", "TEMPORARY"]
}

resource "postgresql_role" "mealie" {
  name                = "mealie_app"
  login               = true
  password_wo         = var.mealie_db_password
  password_wo_version = 2
}

resource "postgresql_database" "mealie" {
  name  = "mealie"
  owner = postgresql_role.mealie.name
}

resource "postgresql_grant" "mealie_revoke_public_database_access" {
  database    = postgresql_database.mealie.name
  role        = "public"
  object_type = "database"
  privileges  = []
}

resource "postgresql_grant" "mealie_connect" {
  database    = postgresql_database.mealie.name
  role        = postgresql_role.mealie.name
  object_type = "database"
  privileges  = ["CONNECT", "CREATE", "TEMPORARY"]
}
