# =======================================================
# platform/network 모듈 state 활용
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
# platform/wazuh 모듈 state 활용
# =======================================================
data "terraform_remote_state" "wazuh" {
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/wazuh/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

locals {
  network = {
    main_vpc_id    = data.terraform_remote_state.network.outputs.main_vpc_id
    cert_subnet_id = data.terraform_remote_state.network.outputs.manager_subnet_id
  }
  policy = {
    ssm_policy_arn = data.terraform_remote_state.wazuh.outputs.ssm_policy_arn
  }
}