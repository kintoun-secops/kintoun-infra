# =======================================================
# 애플리케이션 데이터베이스 사용자
# =======================================================
resource "postgresql_role" "app" {
  name  = local.db_iam_user
  login = true
  roles = ["rds_iam"]
}

# =======================================================
# 권한
# =======================================================
resource "postgresql_grant" "app_connect" {
  database    = local.db_name
  role        = postgresql_role.app.name
  object_type = "database"
  privileges  = ["CONNECT"]
}

resource "postgresql_grant" "app_schema" {
  database    = local.db_name
  role        = postgresql_role.app.name
  schema      = "public"
  object_type = "schema"
  privileges  = ["USAGE", "CREATE"]
}
