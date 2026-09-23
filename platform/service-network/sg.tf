# =======================================================
# Security Group 생성 for ALB
# =======================================================
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-service-alb-sg"
  description = "Security Group for service ALB"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name      = "${var.project_name}-service-alb-sg"
    ManagedBy = "Terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  description = "Allow HTTPS from Internet"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  description = "Allow HTTP for HTTPS redirect"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_frontend" {
  security_group_id = aws_security_group.alb.id

  referenced_security_group_id = aws_security_group.frontend.id
  from_port                    = var.frontend_app_port
  to_port                      = var.frontend_app_port
  ip_protocol                  = "tcp"

  description = "Forward traffic to frontend"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_backend" {
  security_group_id = aws_security_group.alb.id

  referenced_security_group_id = aws_security_group.backend.id
  from_port                    = var.backend_app_port
  to_port                      = var.backend_app_port
  ip_protocol                  = "tcp"

  description = "Forward API traffic to backend"
}

# =======================================================
# Security Group 생성 for 프론트 EC2
# =======================================================
resource "aws_security_group" "frontend" {
  name        = "${var.project_name}-service-frontend-sg"
  description = "Security Group for service frontend EC2"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name      = "${var.project_name}-service-frontend-sg"
    ManagedBy = "Terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "frontend_from_alb" {
  security_group_id = aws_security_group.frontend.id

  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.frontend_app_port
  to_port                      = var.frontend_app_port
  ip_protocol                  = "tcp"

  description = "Allow traffic only from ALB"
}

resource "aws_vpc_security_group_egress_rule" "frontend_outbound" {
  security_group_id = aws_security_group.frontend.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  description = "Allow Outbound for SSM, S3 and package install"
}

# =======================================================
# Security Group 생성 for 백엔드 EC2
# =======================================================
resource "aws_security_group" "backend" {
  name        = "${var.project_name}-service-backend-sg"
  description = "Security Group for service backend EC2"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name      = "${var.project_name}-service-backend-sg"
    ManagedBy = "Terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "backend_from_alb" {
  security_group_id = aws_security_group.backend.id

  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.backend_app_port
  to_port                      = var.backend_app_port
  ip_protocol                  = "tcp"

  description = "Allow application traffic only from ALB"
}

resource "aws_vpc_security_group_egress_rule" "backend_outbound" {
  security_group_id = aws_security_group.backend.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  description = "Allow Outbound for SSM, S3 and package install"
}

resource "aws_vpc_security_group_egress_rule" "backend_to_db" {
  security_group_id = aws_security_group.backend.id

  referenced_security_group_id = aws_security_group.database.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"

  description = "Connect to PostgreSQL"
}

# =======================================================
# Security Group 생성 for RDS
# =======================================================
resource "aws_security_group" "database" {
  name        = "${var.project_name}-service-db-sg"
  description = "Security Group for service RDS"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name      = "${var.project_name}-service-db-sg"
    ManagedBy = "Terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_backend" {
  security_group_id = aws_security_group.database.id

  referenced_security_group_id = aws_security_group.backend.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"

  description = "Allow PostgreSQL only from backend"
}
