# =======================================================
# Security Group 생성 for Uptime Kuma EC2
# =======================================================
resource "aws_security_group" "uptime_kuma_sg" {
  name        = "${var.project_name}-uptime-kuma-sg"
  description = "Security Group for Uptime Kuma EC2"
  vpc_id      = local.network.main_vpc_id

  tags = {
    Name      = "${var.project_name}-uptime-kuma-sg"
    ManagedBy = "Terraform"
  }
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.uptime_kuma_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  description = "Allow Outbound traffic for SSM, Image Pull and HTTPS Monitors"
}
