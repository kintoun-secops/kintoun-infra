# GitHub Actions OIDC 연동 (WBS 2140 기반)
# 2026-08-16 CloudShell 확인 결과 콘솔 수동 생성분 없음 -> import 없이 신규 생성.

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # thumbprint_list 생략: 2023-07부터 AWS가 신뢰 CA 라이브러리로 검증하며
  # provider 5.31+ 에서 optional. tls_certificate 데이터 소스 불필요.
}

# ---- plan 롤: 모든 브랜치·PR 에서 assume 가능, 읽기 전용 ----

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
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "github-actions-plan"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  permissions_boundary = var.permissions_boundary_arn
  description          = "GitHub Actions PR plan 전용 (읽기 + state 접근)"
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
      values   = ["repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "apply" {
  name                 = "github-actions-apply"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  permissions_boundary = var.permissions_boundary_arn
  description          = "GitHub Actions main apply 전용. 최소권한 리팩터링 대상."
}

# ---- state 버킷 접근 (두 롤 공통) ----
# plan 도 기본 동작으로 state 잠금을 잡으므로 두 롤 모두 필요하다.
# use_lockfile 은 락 파일(.tflock) 삭제 때문에 s3:DeleteObject 가
# 추가로 필요하다 (2220 DoD 주석, DynamoDB 방식에는 없던 요구사항).

data "aws_iam_policy_document" "tfstate_access" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]
  }

  statement {
    sid = "ReadWriteStateAndLock"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]
  }
}

resource "aws_iam_policy" "tfstate_access" {
  name        = "gunduun-tfstate-access"
  description = "Terraform 원격 state + .tflock 접근"
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
