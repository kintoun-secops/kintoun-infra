# terraform fmt/validate 가 못 잡는 것만 본다 (미사용 선언, 프로바이더 버전 누락, AWS 인자 값 오류).
# CI lint 잡이 --recursive 로 모든 루트에 돌린다. deep_check(계정 조회)는 쓰지 않는다.

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
