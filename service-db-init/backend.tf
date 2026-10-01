# =======================================================
# 사람이 로컬에서 apply 한다. RDS 가 프라이빗이라 CI 가 닿지 않는다.
# =======================================================
terraform {
  backend "s3" {
    bucket       = "kintoun-tfstate"
    key          = "service-db-init/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}
