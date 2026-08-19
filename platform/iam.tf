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
  policy_arn = aws_iam_policy.wazuh_ssm_role.arn
}

# =======================================================
# Wazuh EC2에 IAM Role 연결을 위한 Profile 생성
# =======================================================
resource "aws_iam_instance_profile" "wazuh_profile" {
  name = "${var.project_name}-wazuh-profile"
  role = aws_iam_role.wazuh_role.name
}

# =======================================================
# Wazuh Dashboard 포트 포워딩 정책
# =======================================================
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "wazuh_port_forwarding" {
  statement {
    sid    = "StartWazuhPortForwarding"
    effect = "Allow"

    actions = [
      "ssm:StartSession"
    ]

    resources = [
      aws_instance.wazuh_ec2.arn,
      "arn:aws:ssm:ap-northeast-2::document/AWS-StartPortForwardingSession"
    ]
  }

  statement {
    sid    = "ManageOwnSession"
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

resource "aws_iam_policy" "wazuh_ssm_port_forwarding" {
  name        = "${var.project_name}-wazuh-ssm-port-forwarding"
  description = "Allow port forwarding to Wazuh Dashboard"
  policy      = data.aws_iam_policy_document.wazuh_port_forwarding.json

  tags = {
    Name = "${var.project_name}-wazuh-ssm-port-forwarding"
  }
}

# =======================================================
# 기존 그룹에 포트 포워딩 정책 연결
# =======================================================
resource "aws_iam_group_policy_attachment" "port_forwarding_group" {
  for_each   = var.port_forwarding_group_names
  group      = each.value
  policy_arn = aws_iam_policy.wazuh_ssm_port_forwarding.arn
}


# =======================================================
# Wazuh 관리자용 정책 (Shell 접속)
# =======================================================
data "aws_iam_policy_document" "wazuh_shell_access" {
  statement {
    sid    = "StartWazuhShellSession"
    effect = "Allow"

    actions = [
      "ssm:StartSession"
    ]

    resources = [
      aws_instance.wazuh_ec2.arn,
      "arn:aws:ssm:ap-northeast-2:${data.aws_caller_identity.current.account_id}:document/SSM-SessionManagerRunShell"
    ]
  }
}

resource "aws_iam_policy" "wazuh_ssm_shell_access" {
  name        = "${var.project_name}-wazuh-ssm-shell-access"
  description = "Allow shell access to Wazuh for Admin"
  policy      = data.aws_iam_policy_document.wazuh_shell_access.json

  tags = {
    Name = "${var.project_name}-wazuh-ssm-shell-access"
  }
}

# =======================================================
# aws login 권한 정책 (임시 자격증명 발급용)
# =======================================================
data "aws_iam_policy_document" "aws_login" {
  statement {
    sid    = "AllowLocalAWSLogin"
    effect = "Allow"

    actions = [
      "signin:AtuhorizeOAuth2Access",
      "sigin:CreateOAuth2Token"
    ]

    resources = [
      "arn:aws:signin:ap-northeast-2:${data.aws_caller_identity.current.account_id}:oauth2/public-client/localhost"
    ]
  }
}

resource "aws_iam_policy" "aws_login" {
  name        = "${var.project_name}-aws-login"
  description = "Allow AWS CLI login using Console for temporary credentials"
  policy      = data.aws_iam_policy_document.aws_login.json

  tags = {
    Name = "${var.project_name}-aws-login"
  }
}

# =======================================================
# 기존 그룹에 aws login 정책 연결
# =======================================================
resource "aws_iam_group_policy_attachment" "aws_login_group" {
  for_each   = var.aws_login_group_names
  group      = each.value
  policy_arn = aws_iam_policy.aws_login.arn
}