# =======================================================
# platform/ 모듈이 apply된 이후에 apply 해야함
# =======================================================
terraform {
  backend "s3" {
    bucket       = "kintoun-tfstate"
    key          = "wazuh-logging/cloudtrail/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}