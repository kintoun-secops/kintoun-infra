variable "bucket_name" {
  type        = string
  description = "생성할 S3 버킷 이름"
}

variable "kms_description" {
  type        = string
  description = "KMS 키 설명"
}

variable "resource_arn" {
  type        = string
  description = "SourceArn 조건에 사용할 리소스 ARN"
  default     = null
}

variable "service_principal" {
  type        = string
  description = "이 버킷에 쓰기 권한을 가질 AWS 서비스 principal"
}

variable "account_id" {
  type        = string
  description = "KMS 키 정책의 root 권한 및 SourceAccount 조건에 사용할 계정 ID"
}

variable "tags" {
  type    = map(string)
  default = {}
}