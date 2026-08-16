# 본 인프라 루트 모듈.
# 2210 (VPC·서브넷·라우팅) 과 2220 (IAM 역할·정책) 코드가 여기에 들어온다.
# 기존 콘솔 생성 IAM(그룹 등)을 편입할 때는 import 블록 +
#   terraform plan -generate-config-out=generated.tf
# 로 역생성해 다듬는다.
#
# bootstrap 의 값이 필요하면 remote state 로 읽는다:
#
# data "terraform_remote_state" "bootstrap" {
#   backend = "s3"
#   config = {
#     bucket = "gunduun-tfstate"
#     key    = "bootstrap/terraform.tfstate"
#     region = "ap-northeast-2"
#   }
# }
