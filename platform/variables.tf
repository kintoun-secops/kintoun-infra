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
  default     = "m6i.large" # 아직 초기단계라서 비용 절약을 우선으로 생각
}
# EC2 Instance Type 비교 (전부 x86_64 여서 인스턴스 타입만 교체 가능)
# =============== m6i.large / c6i.xlarge / m6i.xlarge ===
#             CPU   2v CPU  /   4vCPU    /  4vCPU
#             RAM   8GiB    /    8GiB    /  16GiB
#  Cost(per hour)   0.118   /   0.192    /  0.236  (USD)
# Wazuh All-in-one 공식문서 기준 (agent 1 ~ 25)
# CPU 4vCPU / RAM 8 GiB 
# 현재 인스턴스는 2vCPU로 사용하면서 이후 AWS Native 로그 붙이면서
# 성능 확인하고, 문제 있을 시 올리는걸로 해도 될 것 같음
# 인스턴스 타입 교체는 변수만 바꾸고 apply 하면됨
# 기존 데이터 날라가거나 하지는 않음
# 인스턴스가 중지됐다가 시작하는거라 공인 IP는 변경될거임(현재 EIP 미사용)
# 도메인 기반으로 접속하는게 아니라 공인 IP 변경되도 상관없음
# =======================================================

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

# =======================================================
# IAM Role 경로 접두사 (권한경계가 role/project/* 만 PassRole 허용)
# =======================================================
variable "iam_role_path_prefix" {
  description = "IAM Role 경로 접두사"
  type        = string
  default     = "/project/"

  validation {
    condition     = startswith(var.iam_role_path_prefix, "/project/") && endswith(var.iam_role_path_prefix, "/")
    error_message = "iam_role_path_prefix는 /project/ 로 시작하고 / 로 끝나야 한다."
  }
}
