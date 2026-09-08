# =======================================================
# platform/wazuh 모듈의 tfstate에서 가져오기
# =======================================================
data "terraform_remote_state" "wazuh" {
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/wazuh/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# =======================================================
# platform/network 모듈의 tfstate에서 가져오기
# =======================================================
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/network/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# =======================================================
# platform 모듈의 main_vpc_id, ssm_service 권한 정책
# =======================================================
locals {
  main_vpc_id = data.terraform_remote_state.network.outputs.main_vpc_id
  main_igw_id = data.terraform_remote_state.network.outputs.main_igw_id

  ssm_policy_arn = data.terraform_remote_state.wazuh.outputs.ssm_policy_arn

  wazuh_sg_agent_id = data.terraform_remote_state.wazuh.outputs.wazuh_sg_agent_id
}