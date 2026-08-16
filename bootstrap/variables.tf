variable "github_org" {
  description = "GitHub 조직 이름. OIDC sub 조건(repo:<org>/<repo>)의 좌표가 된다."
  type        = string
}

variable "github_repo" {
  description = "IaC 저장소 이름. 조직 소유 저장소여야 한다."
  type        = string
  default     = "gunduun-infra"
}

variable "state_bucket_name" {
  description = <<-EOT
    Terraform state 버킷 이름. S3 버킷 이름은 전역 유일해야 한다.
    변경 시 bootstrap/backend.tf.example 과 platform/backend.tf 의
    bucket 값도 함께 바꿀 것 (backend 블록은 변수를 못 쓴다).
  EOT
  type        = string
  default     = "gunduun-tfstate"
}

variable "permissions_boundary_arn" {
  description = <<-EOT
    CI 롤에 붙일 권한 경계 정책 ARN.
    팀 IAM 설계상 "새로 생성되는 IAM 개체에 경계 강제"가 걸려 있다면
    이 값 없이는 CreateRole 자체가 거부될 수 있다. 콘솔에서 경계 정책
    이름을 확인해 지정할 것. 예:
      arn:aws:iam::446413909569:policy/<경계정책이름>
  EOT
  type        = string
  default     = null
}

variable "plan_role_policy_arns" {
  description = "plan 롤에 붙일 관리형 정책 (읽기 전용)"
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
}

variable "apply_role_policy_arns" {
  description = <<-EOT
    apply 롤에 붙일 관리형 정책. 기본값(PowerUser + IAMFull)은 사실상
    관리자 수준의 임시 구성이다. 반드시 권한 경계와 함께 쓰고,
    "FullAccess -> 최소권한 리팩터링" 목록에 이 롤을 등재해 축소한다.
  EOT
  type        = list(string)
  default = [
    "arn:aws:iam::aws:policy/PowerUserAccess",
    "arn:aws:iam::aws:policy/IAMFullAccess",
  ]
}
