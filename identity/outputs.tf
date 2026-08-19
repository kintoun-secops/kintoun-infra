output "member_arns" {
  description = "생성된 팀원 IAM User ARN"
  value       = { for name, u in aws_iam_user.member : name => u.arn }
}

output "member_groups" {
  description = "팀원별 소속 그룹"
  value       = { for name, m in var.members : name => sort(tolist(m.groups)) }
}

output "managed_group_arns" {
  description = "이 모듈이 만든 IAM Group ARN"
  value       = { for name, g in aws_iam_group.managed : name => g.arn }
}

output "self_service_policy_arn" {
  description = "셀프 서비스 자격증명 정책 ARN"
  value       = aws_iam_policy.self_service_credentials.arn
}

output "require_mfa_policy_arn" {
  description = "MFA 강제 정책 ARN (enforce_mfa = false 면 null)"
  value       = try(aws_iam_policy.require_mfa[0].arn, null)
}
