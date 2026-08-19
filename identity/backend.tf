# bootstrap 이 버킷을 만든 뒤부터 init 이 동작한다.
# key 를 추가했으면 bootstrap/oidc.tf 의 local.tfstate_keys 에도 넣어야
# CI 롤이 이 state 를 읽고 쓸 수 있다.

terraform {
  backend "s3" {
    bucket       = "kintoun-tfstate" # bootstrap 의 var.state_bucket_name 과 일치해야 함
    key          = "identity/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}
