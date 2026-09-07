# 기존 환경은 이 backend 로 init 한다.
# 버킷이 없는 신규 환경에서만 backend.tf 를 backend.tf.disabled 로 임시 이동해
# 로컬 state 로 최초 apply 한 뒤 복원하고 terraform init -migrate-state 한다.
# 전체 절차: docs/modules/bootstrap.md

terraform {
  backend "s3" {
    bucket       = "kintoun-tfstate" # var.state_bucket_name 과 일치해야 함
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}
