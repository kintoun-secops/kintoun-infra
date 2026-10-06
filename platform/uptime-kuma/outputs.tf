output "uptime_kuma_instance_id" {
  description = "Uptime Kuma EC2 인스턴스 ID"
  value       = aws_instance.uptime_kuma_ec2.id
}

output "uptime_kuma_sg_id" {
  description = "Uptime Kuma 보안 그룹 ID"
  value       = aws_security_group.uptime_kuma_sg.id
}
