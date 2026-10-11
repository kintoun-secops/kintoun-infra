output "association_id" {
  description = "State Manager 연결 ID"
  value       = aws_ssm_association.endpoint_agents.association_id
}

output "document_name" {
  description = "auditd·에이전트 설치 SSM 문서 이름"
  value       = aws_ssm_document.endpoint_agents.name
}

output "target_tag" {
  description = "설치 대상을 고르는 인스턴스 태그"
  value       = "${var.target_tag_key}=${var.target_tag_value}"
}
