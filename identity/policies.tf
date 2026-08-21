# &{aws:username} 은 Terraform 이 IAM 정책 변수 ${aws:username} 로 넘기는 이스케이프다.
locals {
  self_user_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user${var.iam_path}&{aws:username}"
  self_mfa_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:mfa${var.iam_path}&{aws:username}"
}

data "aws_iam_policy_document" "self_service_credentials" {
  statement {
    sid    = "ViewAccountInfo"
    effect = "Allow"
    actions = [
      "iam:GetAccountPasswordPolicy",
      "iam:GetAccountSummary",
      "iam:ListVirtualMFADevices",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageOwnPassword"
    effect = "Allow"
    actions = [
      "iam:ChangePassword",
      "iam:GetUser",
      "iam:GetLoginProfile",
      "iam:UpdateLoginProfile",
    ]
    resources = [local.self_user_arn]
  }

  statement {
    sid    = "ManageOwnAccessKeys"
    effect = "Allow"
    actions = [
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:GetAccessKeyLastUsed",
      "iam:ListAccessKeys",
      "iam:UpdateAccessKey",
    ]
    resources = [local.self_user_arn]
  }

  statement {
    sid    = "EnableOwnMFA"
    effect = "Allow"
    actions = [
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:ListMFADevices",
      "iam:ResyncMFADevice",
    ]
    resources = [local.self_user_arn, local.self_mfa_arn]
  }

  # 기기를 분실하면 본인이 해제할 수 없다 — 관리자가 콘솔에서 처리한다.
  statement {
    sid    = "RemoveOwnMFAWithMFA"
    effect = "Allow"
    actions = [
      "iam:DeactivateMFADevice",
      "iam:DeleteVirtualMFADevice",
    ]
    resources = [local.self_user_arn, local.self_mfa_arn]

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_policy" "self_service_credentials" {
  name        = "${var.project_name}-self-service-credentials"
  path        = var.iam_path
  description = "Let a user manage their own password, access keys and MFA device"
  policy      = data.aws_iam_policy_document.self_service_credentials.json

  tags = merge(local.common_tags, { Name = "${var.project_name}-self-service-credentials" })
}

data "aws_iam_policy_document" "require_mfa" {
  statement {
    sid    = "DenyAllExceptMFASetupWithoutMFA"
    effect = "Deny"

    not_actions = [
      "iam:ChangePassword",
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:GetAccountPasswordPolicy",
      "iam:GetAccountSummary",
      "iam:GetLoginProfile",
      "iam:GetUser",
      "iam:ListMFADevices",
      "iam:ListVirtualMFADevices",
      "iam:ResyncMFADevice",
      "iam:UpdateLoginProfile",
      "sts:GetSessionToken",
    ]
    resources = ["*"]

    # BoolIfExists 라 MFA 키가 아예 없는 요청도 걸린다.
    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_policy" "require_mfa" {
  count = var.enforce_mfa ? 1 : 0

  name        = "${var.project_name}-require-mfa"
  path        = var.iam_path
  description = "Deny everything except MFA enrollment when the session is not MFA authenticated"
  policy      = data.aws_iam_policy_document.require_mfa.json

  tags = merge(local.common_tags, { Name = "${var.project_name}-require-mfa" })
}
