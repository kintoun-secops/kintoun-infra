# =======================================================
# Securtiy Group 생성 for Wazuh EC2
# =======================================================
resource "aws_security_group" "wazuh_sg" {
  name        = "${var.project_name}-wazuh-sg"
  description = "Security Group for Wazuh EC2"
  vpc_id      = aws_vpc.main_vpc.id

  tags = {
    Name = "${var.project_name}-wazuh-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "wazuh_sg_outbound" {
  security_group_id = aws_security_group.wazuh_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  description = "Allow Outbound traffic for SSM and Wazun Install"
}