# =======================================================
# Project Name 변수 (tags 에 활용)
# =======================================================
variable "project_name" {
  description = "tags 에 명시할 프로젝트 이름"
  type        = string
  default     = "kintoun-secops-infra"
}

# =======================================================
# S3 Bucket 이름
# =======================================================
variable "vpc_flow_bucket_name" {
  description = "VPC Flow Logs 저장용 S3 버킷 이름"
  type        = string
  default     = "whs4-kintoun-vpcflow-logs"
}

# =======================================================
# IAM Role 접두사 및 권한 경계
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

variable "permissions_boundary_arn" {
  description = "IAM Role에 붙일 권한경계"
  type        = string
  default     = "arn:aws:iam::446413909569:policy/KintounGuardrailBoundary"
}