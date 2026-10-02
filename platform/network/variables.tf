# 현재 사용 중인 Subnet 대역(중복 되지 않도록 주의)
# CERT : 10.50.10.0/24
# Victim : 10.50.40.0/24
# ALB A : 10.50.110.0/24
# ALB B : 10.50.120.0/24
# NAT : 10.50.130.0/24

variable "project_name" {
  description = "tags 에 명시할 프로젝트 이름"
  type        = string
  default     = "kintoun-secops-infra"
}

<<<<<<< HEAD
=======
variable "iam_role_path_prefix" {
  description = "IAM Role 경로 접두사"
  type        = string
  default     = "/project/"

  validation {
    condition     = startswith(var.iam_role_path_prefix, "/project/") && endswith(var.iam_role_path_prefix, "/")
    error_message = "iam_role_path_prefix는 /project/ 로 시작하고 / 로 끝나야 한다."
  }
}

variable "permissions_boundary_arn" {
  description = "IAM Role에 붙일 권한경계"
  type        = string
  default     = "arn:aws:iam::446413909569:policy/KintounGuardrailBoundary"
}

>>>>>>> origin/main
variable "cert_subnet_cidrs" {
  description = "Wazuh, Velociraptor가 위치할 Subnet IPv4 주소 범위"
  type        = list(string)
  default = [
    "10.50.10.0/24"
  ]

  validation {
    condition = alltrue([
      for cidr in var.cert_subnet_cidrs :
      can(cidrnetmask(cidr))
    ])
    error_message = "cert_subnet_cidrs는 올바른 IPv4 CIDR 형식이어야 한다."
  }

  validation {
    condition = (
      length(var.cert_subnet_cidrs)
      == length(distinct(var.cert_subnet_cidrs))
    )
    error_message = "cert_subnet_cidrs에는 중복된 CIDR를 입력할 수 없다."
  }
}

variable "vpc_cidr" {
  description = "VPC가 사용할 전체 IPv4 주소 범위"
  type        = string
  default     = "10.50.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr는 올바른 IPv4 CIDR 이어야 한다."
  }
}

variable "nat_subnet_cidr" {
<<<<<<< HEAD
  description = "NAT Gateway가 사용할 서브넷 주소 범위"
=======
  description = "NAT 인스턴스가 사용할 서브넷 주소 범위"
>>>>>>> origin/main
  type        = string
  default     = "10.50.130.0/24"

  validation {
    condition     = can(cidrnetmask(var.nat_subnet_cidr))
    error_message = "nat_subnet_cidr는 올바른 IPv4 CIDR 형식이어야 한다."
  }
<<<<<<< HEAD
=======
}

variable "nat_instance_type" {
  description = "NAT 인스턴스에 사용할 EC2 인스턴스 타입"
  type        = string
  default     = "t3.micro"
>>>>>>> origin/main
}