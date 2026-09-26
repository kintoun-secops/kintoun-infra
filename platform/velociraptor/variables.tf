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
  description = "Velociraptor EC2 인스턴스 유형"
  type        = string
  default     = "t3.small" # 시간당 0.026, 2vCPU, 2GiB
}

variable "root_volume_size" {
  description = "Velociraptor 서버 설정 파일 및 Agent 헌트 로그 보관할 루트 EBS 용량"
  type        = number
  default     = 50 # GB

  validation {
    condition     = var.root_volume_size >= 50 # 권장 최소 사양
    error_message = "Root EBS는 최소 50GB 이상으로 설정해야 한다."
  }
}