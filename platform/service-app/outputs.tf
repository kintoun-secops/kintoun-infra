output "service_url" {
  description = "서비스 HTTPS URL"
  value       = "https://${var.service_domain}"
}

output "artifact_bucket" {
  description = "배포 아티팩트 버킷 이름. GitHub 저장소 Variables 에 등록"
  value       = aws_s3_bucket.artifacts.id
}

output "deploy_role_arns" {
  description = "앱별 배포 역할 ARN. 각 저장소 Variables 에 AWS_DEPLOY_ROLE_ARN 으로 등록"
  value       = { for app, r in aws_iam_role.deploy : app => r.arn }
}

output "release_parameters" {
  description = "앱별 현재 릴리스 파라미터 이름"
  value       = local.release_parameters
}

output "frontend_instance_id" {
  description = "프론트 EC2 인스턴스 ID"
  value       = aws_instance.frontend.id
}

output "backend_instance_id" {
  description = "백엔드 EC2 인스턴스 ID"
  value       = aws_instance.backend.id
}

output "alb_dns_name" {
  description = "ALB DNS 이름. Route 53 alias 가 가리킨다"
  value       = aws_lb.main.dns_name
}

output "db_port_forwarding_policy_arn" {
  description = "identity/groups.yaml 의 policy_arns 에 등록해 사람이 터널을 열 수 있게 한다"
  value       = aws_iam_policy.db_port_forwarding.arn
}
