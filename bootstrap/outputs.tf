output "oidc_provider_arn" {
  description = "GitHub OIDC 자격 증명 공급자 ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "plan_role_arn" {
  description = "GitHub 저장소 Variables 에 AWS_PLAN_ROLE_ARN 으로 등록"
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "GitHub 저장소 Variables 에 AWS_APPLY_ROLE_ARN 으로 등록"
  value       = aws_iam_role.apply.arn
}

output "state_bucket" {
  description = "원격 state 버킷 이름"
  value       = aws_s3_bucket.tfstate.id
}
