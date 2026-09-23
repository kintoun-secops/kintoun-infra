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

locals {
  db_endpoint       = data.terraform_remote_state.db.outputs.db_endpoint
  db_port           = data.terraform_remote_state.db.outputs.db_port
  db_name           = data.terraform_remote_state.db.outputs.db_name
  db_iam_user       = data.terraform_remote_state.db.outputs.db_iam_user
  master_secret_arn = data.terraform_remote_state.db.outputs.db_master_secret_arn
}
