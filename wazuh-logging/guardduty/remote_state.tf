# =======================================================
# platform/ 모듈의 tfstate에서 가져오기
# =======================================================
data "terraform_remote_state" "wazuh" { # 이건 남의 state를 읽어오는 것이다.
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/wazuh/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# =======================================================
# platform 모듈의 Wazuh Role Name, Wazuh EC2 ARN
# =======================================================
locals {
  wazuh_role    = data.terraform_remote_state.wazuh.outputs.wazuh_role_name
  wazuh_ec2_arn = data.terraform_remote_state.wazuh.outputs.wazuh_ec2_arn
}
# variable로는 remote_state의 outputs를 data로 불러오는게 불가능
# =======================================================

data "aws_caller_identity" "current" {}