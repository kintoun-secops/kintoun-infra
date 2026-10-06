# =======================================================
# VPC Peering 연결
# =======================================================
resource "aws_vpc_peering_connection" "cert_peer_attacker" {
  peer_vpc_id = local.network.attacker_vpc_id
  vpc_id      = local.network.cert_vpc_id
  auto_accept = true
}

resource "aws_vpc_peering_connection" "cert_peer_service" {
  peer_vpc_id = local.network.service_vpc_id
  vpc_id      = local.network.cert_vpc_id
  auto_accept = true
}

# =======================================================
# VPC Peering Routing (Attacker <-> CERT)
# =======================================================
resource "aws_route" "attacker_to_cert" {
  route_table_id            = local.route_table.attacker_rt_id
  destination_cidr_block    = local.network.cert_subnet_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.cert_peer_attacker.id
}

resource "aws_route" "cert_to_attacker" {
  route_table_id            = local.route_table.cert_rt_id
  destination_cidr_block    = local.network.attacker_subnet_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.cert_peer_attacker.id
}

# =======================================================
# VPC Peering Routing (Service <-> CERT)
# =======================================================
resource "aws_route" "service_to_cert" {
  route_table_id            = local.route_table.service_rt_id
  destination_cidr_block    = local.network.cert_subnet_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.cert_peer_service.id
}

resource "aws_route" "cert_to_service" {
  route_table_id            = local.route_table.cert_rt_id
  destination_cidr_block    = local.network.service_subnet_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.cert_peer_service.id
}

# =======================================================
# Security Group 정책 설정 for Attacker Agent
# =======================================================
resource "aws_vpc_security_group_egress_rule" "attacker_sg_wazuh" {
  security_group_id = local.security_group.attacker_agent_sg_id

  referenced_security_group_id = local.security_group.wazuh_agent_sg_id
  from_port                    = 1514
  to_port                      = 1514
  ip_protocol                  = "tcp"

  description = "Allow Wazuh Agent Traffic Attacker to Wazuh"

  depends_on = [
    aws_vpc_peering_connection.cert_peer_attacker
  ]
}

resource "aws_vpc_security_group_egress_rule" "attacker_sg_wazuh_enroll" {
  security_group_id = local.security_group.attacker_agent_sg_id

  referenced_security_group_id = local.security_group.wazuh_agent_sg_id
  from_port                    = 1515
  to_port                      = 1515
  ip_protocol                  = "tcp"

  description = "Allow Wazuh Agent Enrollment Attacker to Wazuh"

  depends_on = [
    aws_vpc_peering_connection.cert_peer_attacker
  ]
}

resource "aws_vpc_security_group_egress_rule" "attacker_sg_velociraptor" {
  security_group_id = local.security_group.attacker_agent_sg_id

  referenced_security_group_id = local.security_group.velociraptor_agent_sg_id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"

  description = "Allow Velociraptor Agent Traffic Attacker to Velociraptor"

  depends_on = [
    aws_vpc_peering_connection.cert_peer_attacker
  ]
}

# =======================================================
# Security Group 정책 설정 for Service Agent
# =======================================================
resource "aws_vpc_security_group_egress_rule" "frontend_sg_wazuh" {
  security_group_id = local.security_group.frontend_sg_id

  referenced_security_group_id = local.security_group.wazuh_agent_sg_id
  from_port                    = 1514
  to_port                      = 1514
  ip_protocol                  = "tcp"

  description = "Allow Wazuh Agent Traffic Frontend to Wazuh"

  depends_on = [
    aws_vpc_peering_connection.cert_peer_service
  ]
}

resource "aws_vpc_security_group_egress_rule" "frontend_sg_wazuh_enroll" {
  security_group_id = local.security_group.frontend_sg_id

  referenced_security_group_id = local.security_group.wazuh_agent_sg_id
  from_port                    = 1515
  to_port                      = 1515
  ip_protocol                  = "tcp"

  description = "Allow Wazuh Agent Enrollment Frontend to Wazuh"

  depends_on = [
    aws_vpc_peering_connection.cert_peer_service
  ]
}

resource "aws_vpc_security_group_egress_rule" "frontend_sg_velociraptor" {
  security_group_id = local.security_group.frontend_sg_id

  referenced_security_group_id = local.security_group.velociraptor_agent_sg_id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"

  description = "Allow Velociraptor Agent Traffic Frontend to Velociraptor"

  depends_on = [
    aws_vpc_peering_connection.cert_peer_service
  ]
}

resource "aws_vpc_security_group_egress_rule" "backend_sg_wazuh" {
  security_group_id = local.security_group.backend_sg_id

  referenced_security_group_id = local.security_group.wazuh_agent_sg_id
  from_port                    = 1514
  to_port                      = 1514
  ip_protocol                  = "tcp"

  description = "Allow Wazuh Agent Traffic Backend to Wazuh"

  depends_on = [
    aws_vpc_peering_connection.cert_peer_service
  ]
}

resource "aws_vpc_security_group_egress_rule" "backend_sg_wazuh_enroll" {
  security_group_id = local.security_group.backend_sg_id

  referenced_security_group_id = local.security_group.wazuh_agent_sg_id
  from_port                    = 1515
  to_port                      = 1515
  ip_protocol                  = "tcp"

  description = "Allow Wazuh Agent Enrollment Backend to Wazuh"

  depends_on = [
    aws_vpc_peering_connection.cert_peer_service
  ]
}

resource "aws_vpc_security_group_egress_rule" "backend_sg_velociraptor" {
  security_group_id = local.security_group.backend_sg_id

  referenced_security_group_id = local.security_group.velociraptor_agent_sg_id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"

  description = "Allow Velociraptor Agent Traffic Backend to Velociraptor"

  depends_on = [
    aws_vpc_peering_connection.cert_peer_service
  ]
}

# =======================================================
# Security Group 정책 설정 for CERT Agent
# =======================================================
resource "aws_vpc_security_group_ingress_rule" "wazuh_sg_agent" {
  for_each = {
    attacker     = local.security_group.attacker_agent_sg_id
    frontend     = local.security_group.frontend_sg_id
    backend      = local.security_group.backend_sg_id
    velociraptor = local.security_group.velociraptor_agent_sg_id
  }

  security_group_id = local.security_group.wazuh_agent_sg_id

  referenced_security_group_id = each.value
  from_port                    = 1514
  to_port                      = 1514
  ip_protocol                  = "tcp"

  description = "Allow Wazuh Agent Traffic from Agent"

  depends_on = [
    aws_vpc_peering_connection.cert_peer_attacker,
    aws_vpc_peering_connection.cert_peer_service
  ]
}

resource "aws_vpc_security_group_ingress_rule" "wazuh_sg_agent_enroll" {
  for_each = {
    attacker     = local.security_group.attacker_agent_sg_id
    frontend     = local.security_group.frontend_sg_id
    backend      = local.security_group.backend_sg_id
    velociraptor = local.security_group.velociraptor_agent_sg_id
  }

  security_group_id = local.security_group.wazuh_agent_sg_id

  referenced_security_group_id = each.value
  from_port                    = 1515
  to_port                      = 1515
  ip_protocol                  = "tcp"

  description = "Allow Wazuh Agent Enrollment from Agent"

  depends_on = [
    aws_vpc_peering_connection.cert_peer_attacker,
    aws_vpc_peering_connection.cert_peer_service
  ]
}

resource "aws_vpc_security_group_ingress_rule" "velociraptor_sg_agent" {
  for_each = {
    attacker = local.security_group.attacker_agent_sg_id
    frontend = local.security_group.frontend_sg_id
    backend  = local.security_group.backend_sg_id
  }

  security_group_id = local.security_group.velociraptor_agent_sg_id

  referenced_security_group_id = each.value
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"

  description = "Allow Velociraptor Agent Traffic from Agent"

  depends_on = [
    aws_vpc_peering_connection.cert_peer_attacker,
    aws_vpc_peering_connection.cert_peer_service
  ]
}

resource "aws_vpc_security_group_egress_rule" "velociraptor_to_wazuh" {
  security_group_id = local.security_group.velociraptor_agent_sg_id

  referenced_security_group_id = local.security_group.wazuh_agent_sg_id
  from_port                    = 1514
  to_port                      = 1514
  ip_protocol                  = "tcp"

  description = "Allow Wazuh Agent Traffic Velociraptor to Wazuh"
}

resource "aws_vpc_security_group_egress_rule" "velociraptor_to_wazuh_enroll" {
  security_group_id = local.security_group.velociraptor_agent_sg_id

  referenced_security_group_id = local.security_group.wazuh_agent_sg_id
  from_port                    = 1515
  to_port                      = 1515
  ip_protocol                  = "tcp"

  description = "Allow Wazuh Agent Enrollment Velociraptor to Wazuh"
}