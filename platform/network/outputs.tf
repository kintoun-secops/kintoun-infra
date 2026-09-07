output "main_igw_id" {
  description = "Victim 모듈에서 활용할 IGW ID(Wazuh와 동일한 IGW 사용)"
  value       = aws_internet_gateway.main_igw.id
}

output "main_vpc_id" {
  description = "Victim 모듈에서 활용할 VPC ID(wazuh와 동일한 VPC 공유)"
  value       = aws_vpc.main_vpc.id
}

output "manager_subnet_id" {
  description = "Wazuh 매니저가 사용하는 서브넷 ID"
  value       = aws_subnet.public_subnet[0].id
}

output "public_route_table_id" {
  description = "퍼블릭 서브넷 라우팅 테이블 ID"
  value       = aws_route_table.public_route_table.id
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = aws_subnet.public_subnet[*].id
}

output "vpc_cidr" {
  description = "공유 VPC의 IPv4 CIDR"
  value       = aws_vpc.main_vpc.cidr_block
}
