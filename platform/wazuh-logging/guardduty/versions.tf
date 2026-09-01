terraform {
  required_version = ">=1.11" # 이 코드는 테라폼 1.11 이상에서만 돌아간다고 못박는 것

  required_providers {
    aws = {
      source  = "hashicorp/aws" # AWS 리소스를 다루려면 "aws provider"라는 플러그인이 필요하다.
      version = ">=5.31"        # hashicorp/aws 5.31 버전 이상으로 쓰겠다고 선언
    }
  }
}

provider "aws" {
  region = "ap-northeast-2" # 이후 모든 리소스는 별다른 언급 없으면 서울 리전에 만든다.
}