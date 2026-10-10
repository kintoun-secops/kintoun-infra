# =======================================================
# platform/service-network 모듈의 tfstate에서 가져오기
# =======================================================
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/service-network/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# =======================================================
# platform/service-db 모듈의 tfstate에서 가져오기
# =======================================================
data "terraform_remote_state" "db" {
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/service-db/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# =======================================================
# wazuh-logging/alb-log 모듈의 tfstate에서 가져오기
# =======================================================
data "terraform_remote_state" "alb_log" {
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "wazuh-logging/alb-log/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

locals {
  vpc_id            = data.terraform_remote_state.network.outputs.vpc_id
  public_subnet_ids = data.terraform_remote_state.network.outputs.public_subnet_ids
  alb_sg_id         = data.terraform_remote_state.network.outputs.alb_sg_id
  frontend_sg_id    = data.terraform_remote_state.network.outputs.frontend_sg_id
  backend_sg_id     = data.terraform_remote_state.network.outputs.backend_sg_id
  frontend_app_port = data.terraform_remote_state.network.outputs.frontend_app_port
  backend_app_port  = data.terraform_remote_state.network.outputs.backend_app_port
  php_sg_id         = data.terraform_remote_state.network.outputs.php_sg_id
  php_app_port      = data.terraform_remote_state.network.outputs.php_app_port

  db_endpoint    = data.terraform_remote_state.db.outputs.db_endpoint
  db_port        = data.terraform_remote_state.db.outputs.db_port
  db_name        = data.terraform_remote_state.db.outputs.db_name
  db_iam_user    = data.terraform_remote_state.db.outputs.db_iam_user
  db_resource_id = data.terraform_remote_state.db.outputs.db_resource_id

  alb_logs_bucket_name = data.terraform_remote_state.alb_log.outputs.alb_logs_bucket_name
}
