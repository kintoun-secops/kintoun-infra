# =======================================================
# wazuh-logging/vpcflow 모듈에서 remote_tfstate
# =======================================================
output "victim_subnet_id" {
  description = "VPC Flow Logs를 생성할 Subnet ID"
  value       = aws_subnet.victim_public_subnet.id
}

# =======================================================
# Victim EC2 서비스 HTTPS URL
# =======================================================
output "victim_url" {
  description = "Victim EC2 HTTPS URL"
  value       = "https://${var.service_domain}"
}