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
# platform/service-network 모듈의 tfstate에서 가져오기
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
  wazuh_role    = data.terraform_remote_state.wazuh.outputs.wazuh_role_name
  wazuh_ec2_arn = data.terraform_remote_state.wazuh.outputs.wazuh_ec2_arn
  network = {
    service_app_subnet_id = data.terraform_remote_state.service_network.outputs.public_subnet_ids["a"]
    service_db_subnet_id  = data.terraform_remote_state.service_network.outputs.private_subnet_ids["a"]
  }
}
