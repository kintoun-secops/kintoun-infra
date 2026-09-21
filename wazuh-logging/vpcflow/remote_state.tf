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
# victim/ 모듈의 tfstate에서 가져오기
# =======================================================
data "terraform_remote_state" "victim" {
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/victim/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# =======================================================
# platform 모듈의 Wazuh Role Name, Wazuh EC2 ARN, VPC Flow 생성할 Subnet
# =======================================================
locals {
  wazuh_role    = data.terraform_remote_state.wazuh.outputs.wazuh_role_name
  wazuh_ec2_arn = data.terraform_remote_state.wazuh.outputs.wazuh_ec2_arn
}

# ==============s=========================================
# victim 모듈의 Victim Public Subnet
# =======================================================
locals {
  victim_subnet_id = data.terraform_remote_state.victim.outputs.victim_subnet_id
}