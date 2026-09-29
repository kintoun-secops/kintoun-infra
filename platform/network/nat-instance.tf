# =======================================================
# NAT 인스턴스 보안그룹 생성
# =======================================================
resource "aws_security_group" "nat_instance_sg" {
  name        = "${var.project_name}-nat-instance-sg"
  description = "Security Group for NAT Instance"
  vpc_id      = aws_vpc.main_vpc.id

  tags = {
    Name      = "${var.project_name}-nat-instance-sg"
    ManagedBy = "Terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "nat_https_from_cert" {
  for_each = toset(var.cert_subnet_cidrs)

  security_group_id = aws_security_group.nat_instance_sg.id
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"

  description = "Allow HTTPS Traffic from CERT Subnet"
}

resource "aws_vpc_security_group_egress_rule" "nat_https_outbound" {
  security_group_id = aws_security_group.nat_instance_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  description = "Allow Outbound traffic for SSM and Package Update"
}

# =======================================================
# NAT EC2용 IAM Role 생성
# =======================================================
data "aws_iam_policy_document" "nat_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nat_instance_role" {
  name               = "${var.project_name}-nat-instance-role"
  path               = "${var.iam_role_path_prefix}netwrok/"
  assume_role_policy = data.aws_iam_policy_document.nat_assume_role.json

  permissions_boundary = var.permissions_boundary_arn

  tags = {
    Name      = "${var.project_name}-nat-instance-role"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "nat_ssm" {
  role       = aws_aim_role.nat_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nat_instance" {
  name = "${var.project_name}-nat-instance-profile"
  role = aws_iam_role.nat_instance_role.name
}

# =======================================================
# NAT Instance EC2 생성
# =======================================================
data "aws_ssm_parameter" "amazon_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "nat" {
  ami           = data.aws_ssm_parameter.amazon_linux_2023.value
  instance_type = var.nat_instance_type
  subnet_id     = aws_subnet.nat_public_subnet.id

  vpc_security_group_ids = [
    aws_security_group.nat_instance.id
  ]
  iam_instance_profile        = aws_iam_instance_profile.nat_instance.name
  associate_public_ip_address = true
  source_dest_check           = false # 다른 EC2의 통신을 전달하는 EC2 역할
  user_data = templatefile("${path.module}/files/nat-init.sh.tftpl", {
    cert_cidrs = join(" ", var.cert_subnet_cidrs)
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name      = "${var.project_name}-nat-root-volume"
      ManagedBy = "Terraform"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  lifecycle {
    ignore_changes = [
      ami,
      associate_public_ip_address
    ]
  }

  tags = {
    Name      = "${var.project_name}-nat-instance"
    ManagedBy = "Terraform"
  }
}