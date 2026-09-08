# =======================================================
# Trust 생성 for Wazuh EC2
# =======================================================
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# =======================================================
# IAM Role 생성 for Wazuh EC2
# =======================================================
resource "aws_iam_role" "wazuh_role" {
  name               = "${var.project_name}-wazuh-role"
  path               = "${var.iam_role_path_prefix}wazuh/"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  permissions_boundary = var.permissions_boundary_arn

  tags = {
    Name = "${var.project_name}-wazuh-role"
  }
}

# =======================================================
# SSM 사용을 위한 권한 정책 생성 for Wazuh EC
# =======================================================
data "aws_iam_policy_document" "ssm_role" {
  statement {
    effect = "Allow"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ssm_role" {
  name        = "${var.project_name}-ec2-ssm-role"
  description = "Enable SSM management for EC2 Instance"
  policy      = data.aws_iam_policy_document.ssm_role.json

  tags = {
    Name = "${var.project_name}-ec2-ssm-role"
  }
}

resource "aws_iam_policy" "wazuh_ssm_role" {
  name        = "${var.project_name}-wazuh-ec2-ssm-role"
  description = "Enable SSM management for Wazuh EC2"
  policy      = data.aws_iam_policy_document.ssm_role.json

  tags = {
    Name = "${var.project_name}-wazuh-ec2-ssm-role"
  }
}

# =======================================================
# IAM Role에 권한정책 연결
# =======================================================
resource "aws_iam_role_policy_attachment" "wazuh_ssm" {
  role       = aws_iam_role.wazuh_role.name
  policy_arn = aws_iam_policy.ssm_role.arn

  lifecycle {
    create_before_destroy = true
  }
}

# =======================================================
# Wazuh EC2에 IAM Role 연결을 위한 Profile 생성
# =======================================================
resource "aws_iam_instance_profile" "wazuh_profile" {
  name = "${var.project_name}-wazuh-profile"
  role = aws_iam_role.wazuh_role.name
}
