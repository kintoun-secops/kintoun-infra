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
# platform/service-app 모듈의 tfstate에서 가져오기
# (victim 폐지에 따라 WAF Web ACL 출처를 victim -> service-app 으로 변경)
# =======================================================
data "terraform_remote_state" "service_app" {
  backend = "s3"
  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/service-app/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# =======================================================
# platform/wazuh 모듈의 Wazuh Role Name / EC2 ARN
# platform/service-app 모듈의 WAF Web ACL ARN
# =======================================================
locals {
  wazuh_role      = data.terraform_remote_state.platform_wazuh.outputs.wazuh_role_name
  waf_web_acl_arn = data.terraform_remote_state.service_app.outputs.waf_web_acl_arn
}