variable "project_name" {
  description = "tags 에 명시할 프로젝트 이름"
  type        = string
  default     = "kintoun-secops-infra"
}

variable "dry_run" {
  description = "true면 로그만 남기고 실제 차단하지 않음"
  type        = bool
  default     = true
}

variable "ttl_hours" {
  description = "차단 유지 시간(시간)"
  type        = number
  default     = 24
}

variable "max_per_hour" {
  description = "시간당 최대 자동 차단 개수"
  type        = number
  default     = 10
}

variable "allowlist" {
  description = "절대 차단하면 안 되는 CIDR 목록 (팀 IP, NAT 공인 IP 등)"
  type        = list(string)
  default     = []
}