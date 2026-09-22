# =======================================================
# platform/wazuh 모듈 가져오기
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
# wazuh 모듈의 EC2용 SSM 권한 정책 사용(Portforwarding/session manager)
# =======================================================
locals {
  ec2_ssm_policy_arn = data.terraform_remote_state.wazuh.outputs.ssm_policy_arn
}