output "attacker_vpc_id" {
  description = "Attacker VPC ID 출력"
  value       = aws_vpc.attacker_vpc.id
}

output "attacker_subnet_id" {
  description = "Attacker Subent ID 출력"
  value       = aws_subnet.attacker_public_subnet.id
}

output "attacker_subnet_cidr_block" {
  description = "Attacker Subnet IPv4 CIDR 출력"
  value       = aws_subnet.attacker_public_subnet.cidr_block
}

output "attacker_agent_sg_id" {
  description = "Attacker Agent 연결용 SG ID 출력"
  value       = aws_security_group.attacker_agent_sg.id
}

output "attacker_subnet_rt_id" {
  description = "Attacker Subnet에 연결된 Route Table ID 출력"
  value       = aws_route_table.attacker_rt.id
}