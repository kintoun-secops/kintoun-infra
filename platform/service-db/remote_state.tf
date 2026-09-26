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

locals {
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  database_sg_id     = data.terraform_remote_state.network.outputs.database_sg_id
}
