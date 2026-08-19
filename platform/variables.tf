# =======================================================
# Project Name 변수 (tags 에 활용)
# =======================================================
variable "project_name" {
  description = "tags 에 명시할 프로젝트 이름"
  type        = string
  default     = "kintoun-secops-infra"
}

# =======================================================
# 팀 근두운 권한경계
# =======================================================
variable "permissions_boundary_arn" {
  description = "IAM Role에 붙일 권한경계"
  type        = string
  default     = "arn:aws:iam::446413909569:policy/KintounGuardrailBoundary"
}


# =======================================================
# VPC 주소 범위 변수
# =======================================================
variable "vpc_cidr" {
  description = "VPC가 사용할 전체 IPv4 주소 범위"
  type        = string
  default     = "10.50.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr는 올바른 IPv4 CIDR 이어야 한다."
  }
}

# =======================================================
# Public Subnet 주소 범위 변수
# =======================================================
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

# =======================================================
# Wazuh EC2 Instance Type 변수
# =======================================================
variable "instance_type" {
  description = "Wazuh All-in-one EC2 인스턴스 유형"
  type        = string
  default     = "m6i.xlarge"
}

# =======================================================
# Wazuh EC2 EBS 용량 변수 ( 최소 50GB 권장)
# =======================================================
variable "root_volume_size" {
  description = "OS, Wazuh 프로그램 및 설정 파일을 보관할 루트 EBS 용량"
  type        = number
  default     = 100 # GB

  validation {
    condition     = var.root_volume_size >= 50 # Wazuh 공식 문서기준(agent 1 ~ 25, 90일) 최소 권장 용량"
    error_message = "Root EBS는 최소 50GB 이상으로 설정해야 한다."
  }
}

# =======================================================
# aws login 정책 연결용 IAM Group (기존 그룹)
# =======================================================
variable "aws_login_group_names" {
  description = "aws login 정책 연결용 그룹"
  type        = set(string)
  default = [
    "WHS4_Infra",
    "WHS4_Attack",
    "WHS4_SIEM_Detect"
  ]
}

# =======================================================
# 포트 포워딩 정책 연결용 IAM Group (기존 그룹)
# =======================================================
variable "port_forwarding_group_names" {
  description = "포트 포워딩 정책 연결용 그룹"
  type        = set(string)
  default = [
    "WHS4_Infra",
    "WHS4_Attack",
    "WHS4_SIEM_Detect"
  ]
}