# =======================================================
# Security Group 생성 for Velociraptor EC2
# =======================================================
resource "aws_security_group" "velociraptor_sg" {
  name        = "${var.project_name}-velociraptor-sg"
  description = "Security Group for Velociraptor EC2"
  vpc_id      = local.network.main_vpc_id

  tags = {
    Name      = "${var.project_name}-velociraptor-sg"
    ManagedBy = "Terraform"
  }
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.velociraptor_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  description = "Allow Outbound traffic for SSM and Velociraptor Install"
}

resource "aws_security_group" "velociraptor_agent_sg" {
  name        = "${var.project_name}-velociraptor-agent-sg"
  description = "Security Group for Velocirpator Agent Ingress/Egress"
  vpc_id      = local.network.main_vpc_id

  tags = {
    Name      = "${var.project_name}-velociraptor-agent-sg"
    ManagedBy = "Terraform"
  }
}