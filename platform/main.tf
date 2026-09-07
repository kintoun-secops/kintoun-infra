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
      local.wazuh.wazuh_ec2_arn,
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
      local.wazuh.wazuh_ec2_arn,
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
      "signin:CreateOAuth2Token",
      "signin:AuthorizeOAuth2Access"
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
