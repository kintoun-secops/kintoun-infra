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
