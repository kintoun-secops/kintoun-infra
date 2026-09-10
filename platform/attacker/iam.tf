# 공격자용 Attacker EC2에 접속하기 위한 SSM 정책과
# 해당 EC2에 대한 포트포워딩을 열 수 있도록 정책 생성(연결은 identity 모듈에서)
# 그리고, 서버 초기 세팅을 위해 EC2 Shell에 접근할 수 있는 정책 생성

# =======================================================
# IAM Role 생성 for Attacker EC2
# =======================================================
data "aws_iam_policy_document" "attacker_role_trust" {
  statement {
    sid     = "AssumeRoleForAttackerEC2"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "attacker_ec2_role" {
  name               = "${var.project_name}-attacker-ec2-role"
  path               = "${var.iam_role_path_prefix}attacker/"
  assume_role_policy = data.aws_iam_policy_document.attacker_role_trust.json

  permissions_boundary = var.permissions_boundary_arn

  tags = {
    Name      = "${var.project_name}-attacker-ec2-role"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# IAM Role 프로파일 생성 for Attacker EC2
# =======================================================
resource "aws_iam_instance_profile" "attacker_ec2_profile" {
  name = "${var.project_name}-attacker-ec2-profile"
  role = aws_iam_role.attacker_ec2_role.name
}

# =======================================================
# SSM 서비스 권한 정책 for Attacker EC2(platform/wazuh 모듈 활용)
# =======================================================
resource "aws_iam_role_policy_attachment" "attacker_ssm" {
  role       = aws_iam_role.attacker_ec2_role.name
  policy_arn = local.ec2_ssm_policy_arn
}

# =======================================================
# Kali Linux GUI(noVNC 사용을 위한 포트포워딩 정책 생성 for user)
# =======================================================
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kali_port_forwarding" {
  statement {
    sid     = "StartKaliPortForwarding"
    effect  = "Allow"
    actions = ["ssm:StartSession"]
    resources = [
      aws_instance.attacker_ec2.arn,
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

resource "aws_iam_policy" "kali_ssm_port_forwarding" {
  name        = "${var.project_name}-kali-ssm-port-forwarding"
  description = "Allow PortForwarding to Kali Linux GUI"
  policy      = data.aws_iam_policy_document.kali_port_forwarding.json

  tags = {
    Name      = "${var.project_name}-kali-ssm-port-forwarding"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# Kali Linux 초기 설정을 위한 Shell 접속 정책 생성 for user
# =======================================================
data "aws_iam_policy_document" "kali_shell_access" {
  statement {
    sid     = "StartKaliShellSession"
    effect  = "Allow"
    actions = ["ssm:StartSession"]
    resources = [
      aws_instance.attacker_ec2.arn,
      "arn:aws:ssm:ap-northeast-2:${data.aws_caller_identity.current.account_id}:document/SSM-SessionManagerRunShell"
    ]
  }
}

resource "aws_iam_policy" "kali_shell_access" {
  name        = "${var.project_name}-kali-shell-access"
  description = "Allow Shell Access to Kali Linux"
  policy      = data.aws_iam_policy_document.kali_shell_access.json

  tags = {
    Name      = "${var.project_name}-kali-shell-access"
    ManagedBy = "Terraform"
  }
}