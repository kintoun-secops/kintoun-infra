# =======================================================
# platform/service-app 모듈의 tfstate에서 가져오기
# (auto_block IP Set 정보)
# =======================================================
data "terraform_remote_state" "service_app" {
  backend = "s3"
  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/service-app/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

data "terraform_remote_state" "wazuh" {
  backend = "s3"
  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/wazuh/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

locals {
  auto_block_ip_set = data.terraform_remote_state.service_app.outputs.waf_auto_block_ip_set
  wazuh_role        = data.terraform_remote_state.wazuh.outputs.wazuh_role_name
}