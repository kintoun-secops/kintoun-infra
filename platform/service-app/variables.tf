# =======================================================
# 공통
# =======================================================
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

# =======================================================
# 앱 서버
# =======================================================
variable "frontend_instance_type" {
  description = "프론트 EC2 인스턴스 유형"
  type        = string
  default     = "t4g.nano"
}

variable "backend_instance_type" {
  description = "백엔드 EC2 인스턴스 유형"
  type        = string
  default     = "t4g.micro"
}

variable "root_volume_size" {
  description = "앱 서버 루트 EBS 용량(GB)"
  type        = number
  default     = 12

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size는 8 이상이어야 한다."
  }
}

variable "keep_releases" {
  description = "인스턴스 디스크에 남길 최근 릴리스 개수"
  type        = number
  default     = 5

  validation {
    condition     = var.keep_releases >= 1
    error_message = "keep_releases는 1 이상이어야 한다."
  }
}

variable "frontend_health_path" {
  description = "ALB 가 프론트 상태를 확인할 경로"
  type        = string
  default     = "/healthz"
}

variable "backend_health_path" {
  description = "ALB 가 백엔드 상태를 확인할 경로"
  type        = string
  default     = "/api/health"
}

# =======================================================
# 배포
# =======================================================
variable "artifact_bucket_prefix" {
  description = "배포 아티팩트 버킷 이름 접두사"
  type        = string
  default     = "kintoun-service-artifacts"
}

variable "artifact_retention_days" {
  description = "아티팩트 보관 기간(일)"
  type        = number
  default     = 90
}

variable "deploy_repos" {
  description = "앱별 배포 저장소. sub_prefix 는 immutable subject claims 조직에서 실제 sub 로 덮어쓴다"
  type = map(object({
    owner      = string
    repo       = string
    branch     = string
    sub_prefix = optional(string)
  }))
  default = {
    frontend = {
      owner  = "kintoun-secops"
      repo   = "kintoun-frontend"
      branch = "main"
    }
    backend = {
      owner  = "kintoun-secops"
      repo   = "kintoun-backend"
      branch = "main"
    }
  }

  validation {
    condition     = alltrue([for k in keys(var.deploy_repos) : contains(["frontend", "backend"], k)])
    error_message = "deploy_repos의 키는 frontend와 backend 여야 한다."
  }
}

# =======================================================
# 도메인
# =======================================================
variable "service_domain" {
  description = "서비스 FQDN"
  type        = string
  default     = "app.kintoun.work"
}

variable "hosted_zone_name" {
  description = "Route 53에 등록된 Domain 이름"
  type        = string
  default     = "kintoun.work"
}
