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
