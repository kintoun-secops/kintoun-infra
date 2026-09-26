output "main_igw_id" {
  description = "Victim 모듈에서 활용할 IGW ID(Wazuh와 동일한 IGW 사용)"
  value       = aws_internet_gateway.main_igw.id
}

output "main_vpc_id" {
  description = "CERT VPC ID"
  value       = aws_vpc.main_vpc.id
}

output "manager_subnet_id" {
  description = "Wazuh, Velociraptor가 사용하는 서브넷 ID"
  value       = aws_subnet.cert_subnet[0].id
}

output "cert_subnet_cidr_block" {
  description = "Wazuh, Velociraptor가 사용하는 서브넷 IPv4 CIDR"
  value       = aws_subnet.cert_subnet[0].cidr_block
}

output "cert_route_table_id" {
  description = "퍼블릭 서브넷 라우팅 테이블 ID"
  value       = aws_route_table.cert_route_table.id
}

# Wazuh에서 참고하고 있는 state이기 때문에 Plan 오류 방지를 위해 기존 이름 유지
# apply 후 삭제
output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = aws_subnet.cert_subnet[*].id
}
output "cert_subnet_ids" {
  description = "CERT 서브넷 ID 목록"
  value       = aws_subnet.cert_subnet[*].id
}

output "vpc_cidr" {
  description = "공유 VPC의 IPv4 CIDR"
  value       = aws_vpc.main_vpc.cidr_block
}
