# =======================================================
# Security Group 생성 for ALB
# =======================================================
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Security Group for ALB"
  vpc_id      = local.main_vpc_id

  tags = {
    Name     = "${var.project_name}-alb-sg"
    ManageBy = "Terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  description = "Allow HTTPS from Internet"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  description = "Allow HTTP for HTTPS Redirect"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_victim" {
  security_group_id = aws_security_group.alb_sg.id

  referenced_security_group_id = aws_security_group.victim_sg.id
  from_port                    = var.victim_app_port
  to_port                      = var.victim_app_port
  ip_protocol                  = "tcp"

  description = "Forward ALB traffic to Victim"
}



# =======================================================
# Security Group 생성 for Victim EC2 (ALB 통신 및 외부 통신)
# =======================================================
resource "aws_security_group" "victim_sg" {
  name        = "${var.project_name}-victim-sg"
  description = "Security Group for Victim EC2"
  vpc_id      = local.main_vpc_id

  tags = {
    Name     = "${var.project_name}-victim-sg"
    ManageBy = "Terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "victim_from_alb" {
  security_group_id = aws_security_group.victim_sg.id

  referenced_security_group_id = aws_security_group.alb_sg.id
  from_port                    = var.victim_app_port
  to_port                      = var.victim_app_port
  ip_protocol                  = "tcp"

  description = "Allow Application traffic only from ALB"
}

resource "aws_vpc_security_group_egress_rule" "victim_sg_ssm" {
  security_group_id = aws_security_group.victim_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  description = "Allow SSM Agent and Package Install"
}

# =======================================================
# Security Group 생성 for Victim EC2 (Wazuh Agent용)
# =======================================================
resource "aws_security_group" "victim_sg_agent" {
  name        = "${var.project_name}-victim-sg-agent"
  description = "Security Group for Victim EC2 with Wazuh Agent"
  vpc_id      = local.main_vpc_id

  tags = {
    Name     = "${var.project_name}-victim-sg-agent"
    ManageBy = "Terraform"
  }
}

resource "aws_vpc_security_group_egress_rule" "victim_to_wazuh_1514" {
  security_group_id = aws_security_group.victim_sg_agent.id

  referenced_security_group_id = local.wazuh_sg_agent_id
  from_port                    = 1514
  to_port                      = 1514
  ip_protocol                  = "tcp"

  description = "Allow Wazuh Agent Logging"
}

resource "aws_vpc_security_group_egress_rule" "victim_to_wazuh_1515" {
  security_group_id = aws_security_group.victim_sg_agent.id

  referenced_security_group_id = local.wazuh_sg_agent_id
  from_port                    = 1515
  to_port                      = 1515
  ip_protocol                  = "tcp"

  description = "Allow Wazuh Agent Enrollment"
}

# =======================================================
# Security Group 정책 연결 for Wazuh EC2 (Wazuh Agent용)
# =======================================================
resource "aws_vpc_security_group_ingress_rule" "wazuh_from_victim_1514" {
  security_group_id = local.wazuh_sg_agent_id

  referenced_security_group_id = aws_security_group.victim_sg_agent.id
  from_port                    = 1514
  to_port                      = 1514
  ip_protocol                  = "tcp"

  description = "Allow Wazuh Agent Logging from Victim"
}

resource "aws_vpc_security_group_ingress_rule" "wazuh_from_victim_1515" {
  security_group_id = local.wazuh_sg_agent_id

  referenced_security_group_id = aws_security_group.victim_sg_agent.id
  from_port                    = 1515
  to_port                      = 1515
  ip_protocol                  = "tcp"

  description = "Allow Wazuh Agent Enrollment from Victim"
}