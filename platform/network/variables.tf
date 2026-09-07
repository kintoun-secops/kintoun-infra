variable "project_name" {
  description = "tags 에 명시할 프로젝트 이름"
  type        = string
  default     = "kintoun-secops-infra"
}

variable "public_subnet_cidrs" {
  description = "Wazuh EC2가 위치할 Public Subnet IPv4 주소 범위"
  type        = list(string)
  default = [
    "10.50.10.0/24"
  ]

  validation {
    condition = alltrue([
      for cidr in var.public_subnet_cidrs :
      can(cidrnetmask(cidr))
    ])
    error_message = "public_subnet_cidrs는 올바른 IPv4 CIDR 형식 이어야 한다."
  }

  validation {
    condition = (
      length(var.public_subnet_cidrs)
      == length(distinct(var.public_subnet_cidrs))
    )
    error_message = "public_subnet_cidrs에는 중복된 CIDR를 입력할 수 없다."
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
