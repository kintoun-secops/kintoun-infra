# =======================================================
# Project Name 변수 (tags 에 활용)
# =======================================================
variable "project_name" {
  description = "tags 에 명시할 프로젝트 이름"
  type        = string
  default     = "kintoun-secops-infra"
}

# =======================================================
# IAM Role 경로 접두사
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

# =======================================================
# 팀 근두운 권한경계
# =======================================================
variable "permissions_boundary_arn" {
  description = "IAM Role에 붙일 권한경계"
  type        = string
  default     = "arn:aws:iam::446413909569:policy/KintounGuardrailBoundary"
}

# =======================================================
# 공격자용 VPC 주소 범위 변수
# =======================================================
variable "attacker_vpc_cidr" {
  description = "Attacker용 VPC IPv4 CIDR 대역"
  type        = string
  default     = "10.180.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.attacker_vpc_cidr))
    error_message = "attacker_vpc_cidr는 올바른 IPv4 CIDR 형식이어야 한다."
  }
}

# =======================================================
# Attacker EC2 배치할 Public Subnet 주소 범위 변수
# =======================================================
variable "attacker_public_subnet_cidr" {
  description = "Attacker EC2 용 퍼블릭 서브넷 IPv4 CIDR 대역"
  type        = string
  default     = "10.180.40.0/24"

  validation {
    condition     = can(cidrnetmask(var.attacker_public_subnet_cidr))
    error_message = "attacker_public_subnet_cidr는 올바른 IPv4 CIDR 형식이어야 한다."
  }
}

# =======================================================
# Kali Linux AMI ID 변수
# =======================================================
variable "kali_ami_id" {
  description = "AWS Marketplace에서 확인한 Kali Linux AMI ID"
  type        = string
  default     = "ami-0e135ab9f8f216efd" # 2026.2-amd64 버전
}