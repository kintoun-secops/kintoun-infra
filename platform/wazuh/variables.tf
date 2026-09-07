variable "iam_role_path_prefix" {
  description = "IAM Role 경로 접두사"
  type        = string
  default     = "/project/"

  validation {
    condition     = startswith(var.iam_role_path_prefix, "/project/") && endswith(var.iam_role_path_prefix, "/")
    error_message = "iam_role_path_prefix는 /project/ 로 시작하고 / 로 끝나야 한다."
  }
}

variable "instance_type" {
  description = "Wazuh All-in-one EC2 인스턴스 유형"
  type        = string
  default     = "m6i.large" # 아직 초기단계라서 비용 절약을 우선으로 생각
}

variable "permissions_boundary_arn" {
  description = "IAM Role에 붙일 권한경계"
  type        = string
  default     = "arn:aws:iam::446413909569:policy/KintounGuardrailBoundary"
}

variable "project_name" {
  description = "tags 에 명시할 프로젝트 이름"
  type        = string
  default     = "kintoun-secops-infra"
}

variable "root_volume_size" {
  description = "OS, Wazuh 프로그램 및 설정 파일을 보관할 루트 EBS 용량"
  type        = number
  default     = 100 # GB

  validation {
    condition     = var.root_volume_size >= 50 # Wazuh 공식 문서기준(agent 1 ~ 25, 90일) 최소 권장 용량"
    error_message = "Root EBS는 최소 50GB 이상으로 설정해야 한다."
  }
}
