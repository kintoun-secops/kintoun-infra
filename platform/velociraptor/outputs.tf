output "velociraptor_agent_sg_id" {
  description = "Velociraptor Agnet 통신용 보안 그룹 ID"
  value       = aws_security_group.velociraptor_agent_sg.id
}