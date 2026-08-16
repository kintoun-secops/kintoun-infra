# 첫 apply 가 성공한 "다음"에 활성화한다 (버킷이 생기기 전엔 init 이 실패한다):
#
#   mv backend.tf.example backend.tf
#   terraform init -migrate-state
#
# 이후 bootstrap 의 state 도 자기가 만든 버킷 안에서 관리된다 (로컬 state 미보관).

terraform {
  backend "s3" {
    bucket       = "kintoun-tfstate" # var.state_bucket_name 과 일치해야 함
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}
