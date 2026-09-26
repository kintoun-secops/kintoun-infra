# =======================================================
# IAM Role 생성 for Velociraptor EC2 (신뢰 정책 + IAM Role)
# =======================================================
data "aws_iam_policy_document" "velociraptor_role" {
  statement {
    sid     = "AssumeRoleForVelociraptorEC2"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "velociraptor_role" {
  name               = "${var.project_name}-velociraptor-role"
  path               = "${var.iam_role_path_prefix}velociraptor/"
  assume_role_policy = data.aws_iam_policy_document.velociraptor_role.json

  permissions_boundary = var.permissions_boundary_arn

  tags = {
    Name      = "${var.project_name}-velociraptor-role"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# Velociraptor EC2에 IAM Role 연결을 위한 Profile 생성
# =======================================================
resource "aws_iam_instance_profile" "velociraptor_ec2_profile" {
  name = "${var.project_name}-velociraptor-ec2-profile"
  role = aws_iam_role.velociraptor_role.name
}

# =======================================================
# IAM Role에 SSM policy 연결
# =======================================================
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.velociraptor_role.name
  policy_arn = local.policy.ssm_policy_arn
}

# =======================================================
# Velociraptor 대시보드 접속용 포트포워딩 정책
# =======================================================
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "velociraptor_ssm_port_forwarding" {
  statement {
    sid     = "StartVelociraptorPortForwarding"
    effect  = "Allow"
    actions = ["ssm:StartSession"]
    resources = [
      aws_instance.velociraptor_ec2.arn,
      "arn:aws:ssm:ap-northeast-2::document/AWS-StartPortForwardingSession"
    ]
  }

  statement {
    sid    = "SessionManage"
    effect = "Allow"
    actions = [
      "ssmmessages:OpenDataChannel",
      "ssm:ResumeSession",
      "ssm:TerminateSession"
    ]
    resources = [
      "arn:aws:ssm:ap-northeast-2:${data.aws_caller_identity.current.account_id}:session/&{aws:username}-*"
    ]
  }
}

resource "aws_iam_policy" "velociraptor_ssm_port_forwarding" {
  name        = "${var.project_name}-velociraptor-ssm-port-forwarding"
  description = "Allow PortForwarding to Velociraptor Server"
  policy      = data.aws_iam_policy_document.velociraptor_ssm_port_forwarding.json

  tags = {
    Name      = "${var.project_name}-velociraptor-ssm-port-forwarding"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# Velociraptor 서버 Shell 접속 정책
# =======================================================
data "aws_iam_policy_document" "velociraptor_shell_access" {
  statement {
    sid     = "StartVelociraptorShellSession"
    effect  = "Allow"
    actions = ["ssm:StartSession"]
    resources = [
      aws_instance.velociraptor_ec2.arn,
      "arn:aws:ssm:ap-northeast-2:${data.aws_caller_identity.current.account_id}:document/SSM-SessionManagerRunShell"
    ]
  }
}

resource "aws_iam_policy" "velociraptor_shell_access" {
  name        = "${var.project_name}-velociraptor-shell-access"
  description = "Allow Shell Access to Velociraptor Server"
  policy      = data.aws_iam_policy_document.velociraptor_shell_access.json

  tags = {
    Name      = "${var.project_name}-velociraptor-shell-access"
    ManagedBy = "Terraform"
  }
}