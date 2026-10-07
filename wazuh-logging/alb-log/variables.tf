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

variable "alb_log_retention_days" {
  description = "ALB 로그를 S3에 보관할 일수"
  type        = number
  default     = 90

  validation {
    condition = (
      var.alb_log_retention_days >= 1 &&
      floor(var.alb_log_retention_days) == var.alb_log_retention_days
    )
    error_message = "로그 보관 기간은 1 이상의 정수여야 한다."
  }
}

variable "alb_log_bucket_name" {
  description = "ALB Log 저장용 S3 버킷 이름"
  type        = string
  default     = "whs4-kintoun-alb-logs"
}