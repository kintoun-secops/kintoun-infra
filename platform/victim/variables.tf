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
# Victim S3 Bucket 이름
# =======================================================
variable "victim_bucket_name" {
  description = "공격당할 S3 버킷 이름"
  type        = string
  default     = "whs4-kintoun-victim-secrets"
}

# =======================================================
# Public Subnet 주소 범위 변수 (for Victim EC2)
# =======================================================
variable "victim_public_subnet_cidr" {
  description = "Victim EC2가 위치할 Public Subnet IPv4 주소 범위"
  type        = string
  default     = "10.50.40.0/24"

  validation {
    condition     = can(cidrnetmask(var.victim_public_subnet_cidr))
    error_message = "public_subnet_cidr는 올바른 IPv4 CIDR 형식 이어야 한다."
  }
}

# =======================================================
# Public Subnet 주소 범위 변수 (for ALB)
# =======================================================
variable "alb_public_subnets" {
  description = "ALB가 사용할 서로 다른 AZ의 Public Subnets"
  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))
  default = {
    a = {
      cidr_block        = "10.50.110.0/24"
      availability_zone = "ap-northeast-2a"
    }
    b = {
      cidr_block        = "10.50.120.0/24"
      availability_zone = "ap-northeast-2b"
    }
  }
}

# =======================================================
# ALB <-> Victim EC2 통신용 애플리케이션 포트 변수
# =======================================================
variable "victim_app_port" {
  description = "Victim EC2에서 사용할 웹 애플리케이션 포트"
  type        = number
  default     = 80 # Nginx/Apache 서버
}

# =======================================================
# ALB에 연결할 전체 서비스 도메인(FQDN) 변수
# =======================================================
variable "service_domain" {
  description = "ALB에 연결할 서비스 FQDN"
  type        = string
  default     = "service.kintoun.work"
}

# =======================================================
# 구입한 루트 도메인 변수
# =======================================================
variable "hosted_zone_name" {
  description = "Route 53에 등록된 Domain 이름"
  type        = string
  default     = "kintoun.work"
}