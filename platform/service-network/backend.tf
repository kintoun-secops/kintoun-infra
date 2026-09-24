# =======================================================
# platform/service-db 와 platform/service-app 이 이 state 의 출력을 읽는다.
# =======================================================
terraform {
  backend "s3" {
    bucket       = "kintoun-tfstate"
    key          = "platform/service-network/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}
