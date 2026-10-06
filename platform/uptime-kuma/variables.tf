variable "project_name" {
  description = "tags에 명시할 프로젝트 이름"
  type        = string
  default     = "kintoun-secops-infra"
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

variable "instance_type" {
  description = "Uptime Kuma EC2 인스턴스 유형"
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "Uptime Kuma 루트 EBS"
  type        = number
  default     = 20 # GB
}

variable "data_volume_size" {
  description = "Uptime Kuma 데이터 보관 별도 EBS"
  type        = number
  default     = 10 # GB
}

variable "uptime_kuma_image" {
  description = "Uptime Kuma 컨테이너 이미지"
  type        = string
  default     = "louislam/uptime-kuma:2.5.5@sha256:c74379ac4509ce2d2c2633f509e67003ee2e45b6e995c5e43fc101f45a0e1fbe"
}
