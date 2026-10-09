provider "aws" {
  region = var.region
}

# 마스터 비밀번호는 ephemeral 로 읽어 state 와 plan 파일에 남기지 않는다.
ephemeral "aws_secretsmanager_secret_version" "master" {
  secret_id = local.master_secret_arn
}

locals {
  master = jsondecode(ephemeral.aws_secretsmanager_secret_version.master.secret_string)
}

provider "postgresql" {
  host     = coalesce(var.db_host_override, local.db_endpoint)
  port     = coalesce(var.db_port_override, local.db_port)
  database = local.db_name
  username = local.master.username
  password = local.master.password

  # 터널을 쓰면 주소가 127.0.0.1 이라 인증서 호스트 이름 검증이 맞지 않는다.
  sslmode = "require"

  # RDS 마스터는 superuser 가 아니다.
  superuser = false
}
