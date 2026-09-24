variable "project_name" {
  description = "tags 에 명시할 프로젝트 이름"
  type        = string
  default     = "kintoun-secops-infra"
}

variable "region" {
  description = "리소스를 만들 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "vpc_cidr" {
  description = "서비스 VPC 주소 범위"
  type        = string
  default     = "10.60.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr는 올바른 IPv4 CIDR 이어야 한다."
  }
}

variable "public_subnets" {
  description = "앱 서버가 들어갈 퍼블릭 서브넷"
  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))
  default = {
    a = {
      cidr_block        = "10.60.10.0/24"
      availability_zone = "ap-northeast-2a"
    }
    c = {
      cidr_block        = "10.60.20.0/24"
      availability_zone = "ap-northeast-2c"
    }
  }
}

variable "private_subnets" {
  description = "RDS가 들어갈 프라이빗 서브넷"
  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))
  default = {
    a = {
      cidr_block        = "10.60.110.0/24"
      availability_zone = "ap-northeast-2a"
    }
    c = {
      cidr_block        = "10.60.120.0/24"
      availability_zone = "ap-northeast-2c"
    }
  }
}

variable "frontend_app_port" {
  description = "ALB 가 프론트로 보낼 포트"
  type        = number
  default     = 80
}

variable "backend_app_port" {
  description = "ALB 가 백엔드로 보낼 포트"
  type        = number
  default     = 8000
}
