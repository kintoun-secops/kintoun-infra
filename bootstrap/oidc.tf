# GitHub Actions OIDC 연동 (WBS 2140 기반)
# 2026-08-16 CloudShell 확인 결과 콘솔 수동 생성분 없음 -> import 없이 신규 생성.

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # thumbprint_list 생략: 2023-07부터 AWS가 신뢰 CA 라이브러리로 검증하며
  # provider 5.81+ 에서 optional. tls_certificate 데이터 소스 불필요.
}

# sub 조건의 저장소 접두사. immutable subject claims 가 켜진 조직에서는
# 이름이 아니라 숫자 ID 가 박힌 형식이 오므로 var 로 덮어쓴다.
locals {
  github_sub_prefix = coalesce(
    var.github_sub_prefix,
    "repo:${var.github_org}/${var.github_repo}",
  )
}

# ---- plan 롤: 이 레포의 모든 sub(브랜치·태그·PR)에서 assume 가능 ----

data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_sub_prefix}:*"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "github-actions-plan"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  permissions_boundary = var.permissions_boundary_arn
  # IAM description 은 ASCII/Latin-1 만 허용 (한글 불가)
  description = "GitHub Actions PR plan only (read + state access)"
}

# ---- apply 롤: 보호된 main 브랜치에서만 assume 가능 (2110 과 결합) ----

data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_sub_prefix}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "apply" {
  name                 = "github-actions-apply"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  permissions_boundary = var.permissions_boundary_arn
  description          = "GitHub Actions main-branch apply only. Least-privilege refactoring target."
}

# ---- state 버킷 접근 (두 롤 공통) ----
# plan 도 기본 동작으로 state 잠금을 잡으므로 두 롤 모두 필요하다.
# use_lockfile 은 락 파일(.tflock) 삭제 때문에 s3:DeleteObject 가
# 추가로 필요하다 (2220 DoD 주석, DynamoDB 방식에는 없던 요구사항).
# state 키와 락 키를 분리한다 — state 객체에는 Delete 를 주지 않고,
# Delete 는 .tflock 에만 허용한다. 아래 Deny 가 이 불변식을 관리형 정책보다 우선해 지킨다.
#
# state key 는 "<루트 디렉터리>/terraform.tfstate" 로 통일한다 (.github/scripts/tf-roots.js 가 검사).
# IAM 의 * 는 / 를 가로질러 매칭하므로 */terraform.tfstate 하나가 identity/, platform/network/ 처럼
# 깊이 1·2 를 모두 덮는다. 루트 모듈이 늘어도 이 파일과 bootstrap 재적용은 필요 없다.

locals {
  tfstate_key_globs = ["*/terraform.tfstate"]
}

data "aws_iam_policy_document" "tfstate_access" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]
  }

  statement {
    sid = "ReadWriteState"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [for g in local.tfstate_key_globs : "${aws_s3_bucket.tfstate.arn}/${g}"]
  }

  statement {
    sid = "ManageLockFile"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [for g in local.tfstate_key_globs : "${aws_s3_bucket.tfstate.arn}/${g}.tflock"]
  }

  # apply 롤의 PowerUserAccess 가 s3:DeleteObject 를 허용해도 state 객체는 못 지운다.
  statement {
    sid    = "DenyStateObjectDelete"
    effect = "Deny"
    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
    ]
    resources = [for g in local.tfstate_key_globs : "${aws_s3_bucket.tfstate.arn}/${g}"]
  }
}

resource "aws_iam_policy" "tfstate_access" {
  name        = "kintoun-tfstate-access"
  description = "Terraform remote state + .tflock access"
  policy      = data.aws_iam_policy_document.tfstate_access.json
}

resource "aws_iam_role_policy_attachment" "plan_state" {
  role       = aws_iam_role.plan.name
  policy_arn = aws_iam_policy.tfstate_access.arn
}

resource "aws_iam_role_policy_attachment" "apply_state" {
  role       = aws_iam_role.apply.name
  policy_arn = aws_iam_policy.tfstate_access.arn
}

# ---- plan 롤 읽기 가드 ----

data "aws_iam_policy_document" "plan_read_guard" {
  statement {
    sid    = "DenyObjectReadExceptState"
    effect = "Deny"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
    ]
    not_resources = ["${aws_s3_bucket.tfstate.arn}/*"]
  }
}

resource "aws_iam_role_policy" "plan_read_guard" {
  name   = "read-guard"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_read_guard.json
}

# ---- apply 롤 자기 수정 차단 ----
# bootstrap 을 사람이 돌리는 것만으로는 self-modification 이 막히지 않는다.
# apply 롤에는 IAMFullAccess(iam:*) 가 붙어 있으므로, CI 자격 증명이
# 탈취되면 자기 trust policy·경계·정책을 바꿔 권한 상승이 가능하다.
# 명시적 Deny 로 자기 자신과 신뢰 기반(plan 롤, OIDC provider, 경계 정책,
# state 접근 정책)에 대한 변경을 차단한다.

data "aws_iam_policy_document" "apply_self_protect" {
  statement {
    sid    = "DenyCiRoleModification"
    effect = "Deny"
    actions = [
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:DeleteRole",
      "iam:PutRolePermissionsBoundary",
      "iam:DeleteRolePermissionsBoundary",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
    ]
    resources = [
      aws_iam_role.plan.arn,
      aws_iam_role.apply.arn,
    ]
  }

  statement {
    sid    = "DenyTrustAnchorTampering"
    effect = "Deny"
    actions = [
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
    ]
    resources = [aws_iam_openid_connect_provider.github.arn]
  }

  statement {
    sid    = "DenyGuardPolicyTampering"
    effect = "Deny"
    actions = [
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
    ]
    # 경계 정책 자체의 내용 변경도 권한 상승 경로다.
    resources = compact([
      aws_iam_policy.tfstate_access.arn,
      var.permissions_boundary_arn,
    ])
  }
}

resource "aws_iam_role_policy" "apply_self_protect" {
  name   = "self-protect"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_self_protect.json
}

resource "aws_iam_role_policy_attachment" "plan_managed" {
  for_each   = toset(var.plan_role_policy_arns)
  role       = aws_iam_role.plan.name
  policy_arn = each.value
}

resource "aws_iam_role_policy_attachment" "apply_managed" {
  for_each   = toset(var.apply_role_policy_arns)
  role       = aws_iam_role.apply.name
  policy_arn = each.value
}
