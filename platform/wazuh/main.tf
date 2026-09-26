# =======================================================
# Amazon Linux AMI 조회 (ssm:GetParameter 권한 필요)
# =======================================================
data "aws_ssm_parameter" "amazon_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# =======================================================
# EC2 생성 for Wazuh All-in-one
# =======================================================
resource "aws_instance" "wazuh_ec2" {
  ami           = data.aws_ssm_parameter.amazon_linux_2023.value
  instance_type = var.instance_type
  subnet_id     = local.network.cert_subnet_ids[0]

  # Security Group 연결
  vpc_security_group_ids = [
    aws_security_group.wazuh_sg.id,
    aws_security_group.wazuh_sg_agent.id
  ]
  iam_instance_profile        = aws_iam_instance_profile.wazuh_profile.name # IAM Role 연결
  associate_public_ip_address = false                                       # Wazuh 설치때문에 공인 IP 필요, EIP 사용은 공인 IP 고정 필요 시 검토

  # EC2 최초 부팅 시 Wazuh All-in-one 설치 스크립트 실행
  user_data = file("${path.module}/files/wazuh-install.sh")

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = false # EC2 삭제 후에도 Wazuh 데이터 복구를 위해 루트 EBS 보존

    tags = {
      Name = "${var.project_name}-wazuh-root-volume"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 1          # 컨테이너, k8s 미사용 EC2면 "1"이 안전
  }

  # 최신 AMI 교체 방지
  lifecycle {
    ignore_changes = [
      ami
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.wazuh_ssm
  ]

  tags = {
    Name = "${var.project_name}-wazuh-ec2"
  }
}

# =======================================================
# Securtiy Group 생성 for Wazuh EC2
# =======================================================
resource "aws_security_group" "wazuh_sg" {
  name        = "${var.project_name}-wazuh-sg"
  description = "Security Group for Wazuh EC2"
  vpc_id      = local.network.main_vpc_id

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

  description = "Allow Outbound traffic for SSM and Wazuh Install"
}

# =======================================================
# Security Group 생성 for Wazuh EC2 (Wazuh Agent용)
# =======================================================
resource "aws_security_group" "wazuh_sg_agent" {
  name        = "${var.project_name}-wazuh-sg-agent"
  description = "Security Group for Wazuh Agent Logging and Enrollment"
  vpc_id      = local.network.main_vpc_id

  tags = {
    Name     = "${var.project_name}-wazuh-sg-agent"
    ManageBy = "Terraform"
  }
}
