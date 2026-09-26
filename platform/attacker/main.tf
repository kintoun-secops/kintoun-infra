# ============================ Network 설정 ============================ #

# =======================================================
# VPC 생성 for Attacker ##
# =======================================================
resource "aws_vpc" "attacker_vpc" {
  cidr_block = var.attacker_vpc_cidr

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name      = "${var.project_name}-attacker-vpc"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# Internet Gateway 생성 for Attacker
# =======================================================
resource "aws_internet_gateway" "attacker_igw" {
  vpc_id = aws_vpc.attacker_vpc.id

  tags = {
    Name      = "${var.project_name}-attacker-igw"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# Public Subnet 생성 for Attacker
# =======================================================
resource "aws_subnet" "attacker_public_subnet" {
  vpc_id     = aws_vpc.attacker_vpc.id
  cidr_block = var.attacker_public_subnet_cidr

  map_public_ip_on_launch = false

  tags = {
    Name      = "${var.project_name}-attacker-public-subnet"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# Route Table 생성 및 라우팅
# =======================================================
resource "aws_route_table" "attacker_rt" {
  vpc_id = aws_vpc.attacker_vpc.id

  tags = {
    Name      = "${var.project_name}-attacker-rt"
    ManagedBy = "Terraform"
  }
}

resource "aws_route" "attacker_to_internet" {
  route_table_id         = aws_route_table.attacker_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.attacker_igw.id
}

resource "aws_route_table_association" "attacker_rt_association" {
  subnet_id      = aws_subnet.attacker_public_subnet.id
  route_table_id = aws_route_table.attacker_rt.id
}

# ============================ EC2 생성 =============================== #

# =======================================================
# Attacker EC2 (Kali Linux) 생성
# =======================================================
resource "aws_instance" "attacker_ec2" {
  ami           = var.kali_ami_id
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.attacker_public_subnet.id
  vpc_security_group_ids = [
    aws_security_group.attacker_sg.id,
    aws_security_group.attacker_agent_sg.id
  ]
  iam_instance_profile        = aws_iam_instance_profile.attacker_ec2_profile.name
  associate_public_ip_address = true

  user_data                   = file("${path.module}/files/kali-install.sh")
  user_data_replace_on_change = false

  root_block_device {
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  lifecycle {
    ignore_changes = [
      ami,
      associate_public_ip_address
    ]
  }

  tags = {
    Name      = "${var.project_name}-kali-attacker-ec2"
    ManagedBy = "Terraform"
  }

  volume_tags = {
    Name      = "${var.project_name}-kali-attacker-ec2-root-volume"
    ManagedBy = "Terraform"
  }
}

# ============================ 보안그룹 설정 ============================ #

# =======================================================
# Security Group 생성 for Attacker EC2
# =======================================================
resource "aws_security_group" "attacker_sg" {
  name        = "${var.project_name}-attacker-sg"
  description = "Security Group for Attacker EC2"
  vpc_id      = aws_vpc.attacker_vpc.id

  tags = {
    Name      = "${var.project_name}-attacker-sg"
    ManagedBy = "Terraform"
  }
}

resource "aws_vpc_security_group_egress_rule" "attacker_ec2_https" {
  security_group_id = aws_security_group.attacker_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  description = "SSM Service and Package Install and ALB access"
}

resource "aws_security_group" "attacker_agent_sg" {
  name        = "${var.project_name}-attacker-agent-sg"
  description = "Security Group for Attacker Agent Connection"
  vpc_id      = aws_vpc.attacker_vpc.id

  tags = {
    Name      = "${var.project_name}-attacker-agent-sg"
    ManagedBy = "Terraform"
  }
}