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

variable "db_instance_class" {
  description = "RDS 인스턴스 클래스"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "RDS 스토리지 용량(GB)"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "RDS 자동 확장 상한(GB)"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "최초 생성할 데이터베이스 이름"
  type        = string
  default     = "appdb"
}

variable "db_master_username" {
  description = "스키마 마이그레이션에만 쓰는 마스터 사용자"
  type        = string
  default     = "dbadmin"
}

variable "db_iam_user" {
  description = "백엔드가 IAM 인증으로 접속할 데이터베이스 사용자"
  type        = string
  default     = "app"
}

variable "db_multi_az" {
  description = "RDS Multi-AZ 사용 여부"
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "RDS 자동 백업 보관 기간(일)"
  type        = number
  default     = 1
}

variable "db_deletion_protection" {
  description = "RDS 삭제 보호"
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "RDS 삭제 시 최종 스냅샷 생략"
  type        = bool
  default     = false
}

variable "db_state" {
  description = "RDS 인스턴스가 유지해야 할 상태"
  type        = string
  default     = "available"

  validation {
    condition     = contains(["available", "stopped"], var.db_state)
    error_message = "db_state는 available 또는 stopped 여야 한다."
  }
}
