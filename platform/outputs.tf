output "wazuh_instance_id" {
  description = "SSM 세션 연결에 사용할 Wazuh EC2 Instance ID"
  value       = aws_instance.wazuh_ec2.id
}

output "ssm_port_forward_command" {
  description = "Wazuh Dashboard 접속을 위한 SSM 포트 포워딩 커맨드"
  value       = <<-EOT
        aws ssm start-session \
        --target ${aws_instance.wazuh_ec2.id} \
        --document-name AWS-StartPortForwardingSession \
        --parameters '{"portNumber":["443"],"localPortNumber":["56789"]}' \
        --region ap-northeast-2
    EOT
}

output "wazuh_dashboard_url" {
  description = "SSM 포트 포워딩 실행 후 접속할 로컬 주소"
  value       = "https://localhost:56789"
}

# =======================================================
# wazuh-logging 모듈에서 remote_tfstate
# =======================================================
output "wazuh_role_name" {
  description = "AWS Native Logging을 위한 logging/에서 Wazuh 정책 이름 사용"
  value       = aws_iam_role.wazuh_role.name
}

output "wazuh_ec2_arn" {
  description = "AWS Native Logging을 위한 logging/에서 Wazuh EC2 ARN 사용"
  value       = aws_instance.wazuh_ec2.arn
}

# =======================================================
# victim 모듈에서 remote_tfstate
# =======================================================
output "main_vpc_id" {
  description = "Victim 모듈에서 활용할 VPC ID(wazuh와 동일한 VPC 공유)"
  value       = aws_vpc.main_vpc.id
}

output "main_igw_id" {
  description = "Victim 모듈에서 활용할 IGW ID(Wazuh와 동일한 IGW 사용)"
  value       = aws_internet_gateway.main_igw.id
}

# Attacker 모듈에서도 remote_tfstate
output "ssm_policy_arn" {
  description = "Victim EC2 SSM 서비스 사용을 위한 권한 정책 ARN"
  value       = aws_iam_policy.wazuh_ssm_role.arn
}

output "wazuh_sg_agent_id" {
  description = "Victim 모듈에서 Wazuh Agent용 ingress/egress 정책 적용"
  value       = aws_security_group.wazuh_sg_agent.id
}