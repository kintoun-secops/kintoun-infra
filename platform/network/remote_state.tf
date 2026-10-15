# =======================================================
# platform/service-network 모듈 state 활용
# =======================================================
data "terraform_remote_state" "service_network" {
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/service-network/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

locals {
  network = {
    service_vpc_id = data.terraform_remote_state.service_network.outputs.vpc_id
  }
}