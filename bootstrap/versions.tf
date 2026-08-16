terraform {
  # use_lockfile 이 GA 된 첫 버전. WBS 2120 DoD 항목이기도 하다.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # aws_iam_openid_connect_provider 의 thumbprint_list 가 optional 이 된
      # 버전은 v5.81.0 (2024-12) — 그 미만에서는 생략 시 검증 에러가 난다.
      version = ">= 5.81"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}
