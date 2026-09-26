output "vpc_id" {
  description = "서비스 VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "서비스 VPC 주소 범위"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_cidr_blocks" {
  description = "AZ 키로 서브넷 IPv4 CIDR 출력"
  value       = { for k, s in aws_subnet.public : k => s.cidr_block }
}

output "public_subnet_rt_id" {
  description = "WEB, WAS 서브넷 라우트 테이블 ID"
  value       = aws_route_table.public.id
}

output "public_subnet_ids" {
  description = "AZ 키로 찾는 퍼블릭 서브넷 ID"
  value       = { for k, s in aws_subnet.public : k => s.id }
}

output "private_subnet_ids" {
  description = "AZ 키로 찾는 프라이빗 서브넷 ID"
  value       = { for k, s in aws_subnet.private : k => s.id }
}

output "frontend_sg_id" {
  description = "프론트 EC2 보안 그룹 ID"
  value       = aws_security_group.frontend.id
}

output "backend_sg_id" {
  description = "백엔드 EC2 보안 그룹 ID"
  value       = aws_security_group.backend.id
}

output "database_sg_id" {
  description = "RDS 보안 그룹 ID"
  value       = aws_security_group.database.id
}

output "backend_app_port" {
  description = "보안 그룹 규칙과 애플리케이션이 함께 쓰는 포트"
  value       = var.backend_app_port
}

output "alb_sg_id" {
  description = "ALB 보안 그룹 ID"
  value       = aws_security_group.alb.id
}

output "frontend_app_port" {
  description = "ALB 가 프론트로 보내는 포트"
  value       = var.frontend_app_port
}
