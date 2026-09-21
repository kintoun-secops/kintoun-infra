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