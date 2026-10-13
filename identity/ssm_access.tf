# =======================================================
# 태그 기반 SSM 접속 정책
# =======================================================
locals {
  ssm_instance_arn = "arn:aws:ec2:ap-northeast-2:${data.aws_caller_identity.current.account_id}:instance/*"
  ssm_session_arn  = "arn:aws:ssm:ap-northeast-2:${data.aws_caller_identity.current.account_id}:session/&{aws:username}-*"
  ssm_shell_teams  = toset(["attack", "siem", "php"])
}

data "aws_iam_policy_document" "ssm_port_forwarding" {
  statement {
    sid       = "StartPortForwardingOnTaggedInstances"
    effect    = "Allow"
    actions   = ["ssm:StartSession"]
    resources = [local.ssm_instance_arn]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/SSMPortForward"
      values   = ["true"]
    }
  }

  statement {
    sid       = "UsePortForwardingDocument"
    effect    = "Allow"
    actions   = ["ssm:StartSession"]
    resources = ["arn:aws:ssm:ap-northeast-2::document/AWS-StartPortForwardingSession"]
  }

  statement {
    sid    = "ManageOwnSession"
    effect = "Allow"
    actions = [
      "ssmmessages:OpenDataChannel",
      "ssm:ResumeSession",
      "ssm:TerminateSession",
    ]
    resources = [local.ssm_session_arn]
  }
}

resource "aws_iam_policy" "ssm_port_forwarding" {
  name        = "${var.project_name}-ssm-port-forwarding"
  path        = var.iam_path
  description = "Allow SSM port forwarding to instances tagged SSMPortForward=true"
  policy      = data.aws_iam_policy_document.ssm_port_forwarding.json

  tags = merge(local.common_tags, { Name = "${var.project_name}-ssm-port-forwarding" })
}

data "aws_iam_policy_document" "ssm_shell" {
  for_each = local.ssm_shell_teams

  statement {
    sid       = "StartShellOnTaggedInstances"
    effect    = "Allow"
    actions   = ["ssm:StartSession"]
    resources = [local.ssm_instance_arn]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/SSMShell"
      values   = [each.key]
    }
  }

  statement {
    sid       = "UseShellDocument"
    effect    = "Allow"
    actions   = ["ssm:StartSession"]
    resources = ["arn:aws:ssm:ap-northeast-2:${data.aws_caller_identity.current.account_id}:document/SSM-SessionManagerRunShell"]
  }

  statement {
    sid    = "ManageOwnSession"
    effect = "Allow"
    actions = [
      "ssmmessages:OpenDataChannel",
      "ssm:ResumeSession",
      "ssm:TerminateSession",
    ]
    resources = [local.ssm_session_arn]
  }
}

resource "aws_iam_policy" "ssm_shell" {
  for_each = local.ssm_shell_teams

  name        = "${var.project_name}-ssm-shell-${each.key}"
  path        = var.iam_path
  description = "Allow SSM shell to instances tagged SSMShell=${each.key}"
  policy      = data.aws_iam_policy_document.ssm_shell[each.key].json

  tags = merge(local.common_tags, { Name = "${var.project_name}-ssm-shell-${each.key}" })
}

# =======================================================
# 태그 기반 EC2 전원 on/off 정책
# =======================================================
data "aws_iam_policy_document" "ec2_power" {
  statement {
    sid       = "StartStopTaggedInstances"
    effect    = "Allow"
    actions   = ["ec2:StartInstances", "ec2:StopInstances"]
    resources = [local.ssm_instance_arn]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/SSMPortForward"
      values   = ["true"]
    }
  }
}

resource "aws_iam_policy" "ec2_power" {
  name        = "${var.project_name}-ec2-power"
  path        = var.iam_path
  description = "Allow starting and stopping instances tagged SSMPortForward=true"
  policy      = data.aws_iam_policy_document.ec2_power.json

  tags = merge(local.common_tags, { Name = "${var.project_name}-ec2-power" })
}

# =======================================================
# SSM 접속 대상 조회 정책
# =======================================================
# 셸·포트포워딩 정책은 인스턴스 ID 를 받아 세션을 연다. 그 ID 를 조회할
# 권한이 없으면 접속 권한이 있어도 대상을 특정할 수 없다. 목록 조회만 연다.
#
# ec2:DescribeInstances 와 ssm:DescribeInstanceInformation 은 리소스 수준
# 권한을 지원하지 않아 Resource 를 "*" 로 둘 수밖에 없다. 인스턴스 목록과
# 태그가 노출되지만, 접속 자체는 기존 SSMShell·SSMPortForward 태그 조건이
# 그대로 통제한다. 태그 변경은 아래 ssm_tag_guard 가 계속 막는다.
data "aws_iam_policy_document" "ssm_instance_discovery" {
  statement {
    sid    = "ListInstancesForSessionTargeting"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ssm:DescribeInstanceInformation",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ssm_instance_discovery" {
  name        = "${var.project_name}-ssm-instance-discovery"
  path        = var.iam_path
  description = "Read-only instance listing so SSM session targets can be resolved"
  policy      = data.aws_iam_policy_document.ssm_instance_discovery.json

  tags = merge(local.common_tags, { Name = "${var.project_name}-ssm-instance-discovery" })
}

# 특정 그룹이 아니라 전원에게 붙인다. 접속 대상을 찾는 일은 팀 공통이고,
# 그룹별로 달면 새 그룹이 생길 때마다 같은 구멍이 다시 난다.
# ssm_tag_guard 와 같은 방식이다.
resource "aws_iam_user_policy_attachment" "ssm_instance_discovery" {
  for_each = local.members

  user       = aws_iam_user.member[each.key].name
  policy_arn = aws_iam_policy.ssm_instance_discovery.arn
}

# =======================================================
# SIEM 대시보드 포트포워딩 정책
# =======================================================
# Wazuh·Velociraptor 대시보드를 로컬에서 열기 위한 터널이다. 대상은
# SSMShell=siem 인 두 인스턴스로 한정한다. 기존 ssm-port-forwarding 은
# SSMPortForward=true 인 네 대(attacker, service-app 포함) 전부를 열지만,
# 대시보드 열람 목적에는 그만큼이 필요하지 않다.
#
# 셸이 아니라 포트포워딩 문서만 허용하므로 이 정책으로는 명령을 실행할 수
# 없다. 셸은 ssm-shell-siem 이 따로 통제한다.
data "aws_iam_policy_document" "ssm_port_forward_siem" {
  statement {
    sid       = "StartPortForwardingOnSiemInstances"
    effect    = "Allow"
    actions   = ["ssm:StartSession"]
    resources = [local.ssm_instance_arn]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/SSMShell"
      values   = ["siem"]
    }
  }

  statement {
    sid       = "UsePortForwardingDocument"
    effect    = "Allow"
    actions   = ["ssm:StartSession"]
    resources = ["arn:aws:ssm:ap-northeast-2::document/AWS-StartPortForwardingSession"]
  }

  statement {
    sid    = "ManageOwnSession"
    effect = "Allow"
    actions = [
      "ssmmessages:OpenDataChannel",
      "ssm:ResumeSession",
      "ssm:TerminateSession",
    ]
    resources = [local.ssm_session_arn]
  }
}

resource "aws_iam_policy" "ssm_port_forward_siem" {
  name        = "${var.project_name}-ssm-port-forward-siem"
  path        = var.iam_path
  description = "Allow port forwarding to SIEM dashboards (instances tagged SSMShell=siem)"
  policy      = data.aws_iam_policy_document.ssm_port_forward_siem.json

  tags = merge(local.common_tags, { Name = "${var.project_name}-ssm-port-forward-siem" })
}

resource "aws_iam_user_policy_attachment" "ssm_port_forward_siem" {
  for_each = local.members

  user       = aws_iam_user.member[each.key].name
  policy_arn = aws_iam_policy.ssm_port_forward_siem.arn
}

# =======================================================
# SSM 접속 태그 변경 차단
# =======================================================
data "aws_iam_policy_document" "ssm_tag_guard" {
  statement {
    sid       = "DenySSMAccessTagChanges"
    effect    = "Deny"
    actions   = ["ec2:CreateTags", "ec2:DeleteTags"]
    resources = ["*"]

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "aws:TagKeys"
      values   = ["SSMPortForward", "SSMShell"]
    }
  }
}

resource "aws_iam_policy" "ssm_tag_guard" {
  name        = "${var.project_name}-ssm-tag-guard"
  path        = var.iam_path
  description = "Deny team members from changing SSM access tags"
  policy      = data.aws_iam_policy_document.ssm_tag_guard.json

  tags = merge(local.common_tags, { Name = "${var.project_name}-ssm-tag-guard" })
}

resource "aws_iam_user_policy_attachment" "ssm_tag_guard" {
  for_each = local.members

  user       = aws_iam_user.member[each.key].name
  policy_arn = aws_iam_policy.ssm_tag_guard.arn
}
