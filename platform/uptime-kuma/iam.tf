# =======================================================
# IAM Role 생성 for Uptime Kuma EC2 (신뢰 정책 + IAM Role)
# =======================================================
data "aws_iam_policy_document" "uptime_kuma_role" {
  statement {
    sid     = "AssumeRoleForUptimeKumaEC2"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "uptime_kuma_role" {
  name               = "${var.project_name}-uptime-kuma-role"
  path               = "${var.iam_role_path_prefix}uptime-kuma/"
  assume_role_policy = data.aws_iam_policy_document.uptime_kuma_role.json

  permissions_boundary = var.permissions_boundary_arn

  tags = {
    Name      = "${var.project_name}-uptime-kuma-role"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# Uptime Kuma EC2에 IAM Role 연결을 위한 Profile 생성
# =======================================================
resource "aws_iam_instance_profile" "uptime_kuma_ec2_profile" {
  name = "${var.project_name}-uptime-kuma-ec2-profile"
  role = aws_iam_role.uptime_kuma_role.name
}

# =======================================================
# IAM Role에 SSM policy 연결
# =======================================================
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.uptime_kuma_role.name
  policy_arn = local.policy.ssm_policy_arn
}
