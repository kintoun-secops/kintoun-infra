# =======================================================
# platform/network, platform/wazuh 모듈 apply 이후 apply
# =======================================================
terraform {
  backend "s3" {
    bucket       = "kintoun-tfstate"
    key          = "platform/uptime-kuma/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}
