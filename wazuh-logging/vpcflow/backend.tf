# =======================================================
# platform/ 모듈이 apply된 이후에 apply
# =======================================================
terraform {
  backend "s3" {
    bucket       = "kintoun-tfstate"
    key          = "wazuh-logging/vpcflow/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}