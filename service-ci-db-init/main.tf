# =======================================================
# CI 데이터베이스 사용자
# =======================================================
resource "postgresql_role" "ci" {
  name     = local.db_iam_user
  login    = true
  password = var.ci_db_password
}

# =======================================================
# 권한
# =======================================================
resource "postgresql_grant" "ci_connect" {
  database    = local.db_name
  role        = postgresql_role.ci.name
  object_type = "database"
  privileges  = ["CONNECT"]
}

resource "postgresql_grant" "ci_schema" {
  database    = local.db_name
  role        = postgresql_role.ci.name
  schema      = "public"
  object_type = "schema"
  privileges  = ["USAGE", "CREATE"]
}
