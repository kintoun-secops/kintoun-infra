# =======================================================
# platform/wazuh 모듈의 tfstate에서 가져오기
# =======================================================
data "terraform_remote_state" "platform_wazuh" {
  backend = "s3"
  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/wazuh/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# =======================================================
# platform/victim 모듈의 tfstate에서 가져오기
# platform/victim에 waf_web_acl_arn output 추가 
# WAF apply 완료 후 주석 해제
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
# platform/wazuh 모듈의 Wazuh Role Name / EC2 ARN
# platform/victim 모듈의 WAF Web ACL ARN
# =======================================================
locals {
  wazuh_role      = data.terraform_remote_state.platform_wazuh.outputs.wazuh_role_name
  waf_web_acl_arn = data.terraform_remote_state.victim.outputs.waf_web_acl_arn
}