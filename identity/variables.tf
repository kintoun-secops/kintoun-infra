variable "project_name" {
  description = "tags 에 명시할 프로젝트 이름"
  type        = string
  default     = "kintoun-secops-infra"
}

variable "permissions_boundary_arn" {
  description = "팀원 IAM User 에 붙일 권한경계"
  type        = string
  default     = "arn:aws:iam::446413909569:policy/KintounGuardrailBoundary"
}

variable "iam_path" {
  description = "이 모듈이 만드는 IAM User/Group 의 경로"
  type        = string
  default     = "/"

  validation {
    condition     = startswith(var.iam_path, "/") && endswith(var.iam_path, "/")
    error_message = "iam_path 는 / 로 시작하고 / 로 끝나야 한다."
  }
}

variable "enforce_mfa" {
  description = "MFA 미인증 세션의 모든 동작을 Deny 할지 여부"
  type        = bool
  default     = true
}

variable "force_destroy_users" {
  description = "명단에서 뺀 사용자를 로그인 프로필·키·MFA 까지 정리하며 삭제"
  type        = bool
  default     = true
}
