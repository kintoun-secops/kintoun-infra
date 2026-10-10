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

# =======================================================
# php 사용자 (비밀번호 로그인)
# =======================================================
resource "postgresql_role" "php" {
  name     = "php"
  login    = true
  password = var.php_db_password
}

resource "postgresql_grant" "php_connect" {
  database    = local.db_name
  role        = postgresql_role.php.name
  object_type = "database"
  privileges  = ["CONNECT"]
}

resource "postgresql_grant" "php_schema" {
  database    = local.db_name
  role        = postgresql_role.php.name
  schema      = "public"
  object_type = "schema"
  privileges  = ["USAGE"]
}
