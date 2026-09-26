# =======================================================
# platform/network 모듈 apply 이후 apply
# =======================================================
terraform {
  backend "s3" {
    bucket       = "kintoun-tfstate"
    key          = "platform/velociraptor/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}