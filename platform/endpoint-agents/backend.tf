# =======================================================
# platform/wazuh, platform/velociraptor 모듈 apply 이후 apply
# =======================================================
terraform {
  backend "s3" {
    bucket       = "kintoun-tfstate"
    key          = "platform/endpoint-agents/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}
