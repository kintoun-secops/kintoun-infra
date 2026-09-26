output "db_identifier" {
  description = "RDS 인스턴스 식별자. 예약 워크플로가 상태를 조회할 때 쓴다"
  value       = aws_db_instance.main.identifier
}

output "db_endpoint" {
  description = "RDS 접속 주소"
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "RDS 접속 포트"
  value       = aws_db_instance.main.port
}

output "db_resource_id" {
  description = "rds-db:connect 정책 ARN 에 쓰는 리소스 ID. 인스턴스 식별자와 다르다"
  value       = aws_db_instance.main.resource_id
}

output "db_name" {
  description = "데이터베이스 이름"
  value       = var.db_name
}

output "db_iam_user" {
  description = "백엔드가 IAM 인증으로 접속하는 사용자"
  value       = var.db_iam_user
}

output "db_master_secret_arn" {
  description = "AWS 가 관리하는 마스터 비밀번호 시크릿 ARN. 스키마 마이그레이션에만 쓴다"
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "master_secret_read_policy_arn" {
  description = "identity/groups.yaml 의 policy_arns 에 등록해 사람이 마스터 비밀번호를 읽게 한다"
  value       = aws_iam_policy.master_secret_read.arn
}
