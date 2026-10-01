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
# =======================================================
# platform/attacker 모듈 state 활용
# =======================================================
/*data "terraform_remote_state" "attacker" {
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/attacker/terraform.tfstate"
    region = "ap-northeast-2"
  }
}*/ # 후속 PR에서 처리

locals {
  network = {
    service_vpc_id = data.terraform_remote_state.service_network.outputs.vpc_id
    # 후속 PR에서 처리 attacker_vpc_id = data.terraform_remote_state.attacker.outputs.attacker_vpc_id
  }
}