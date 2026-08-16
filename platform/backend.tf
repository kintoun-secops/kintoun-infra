# bootstrap 이 버킷을 만든 뒤부터 init 이 동작한다.
# 이 디렉터리는 처음부터 원격 state 로 시작하므로 마이그레이션이 없다.

terraform {
  backend "s3" {
    bucket       = "kintoun-tfstate" # bootstrap 의 var.state_bucket_name 과 일치해야 함
    key          = "platform/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}
