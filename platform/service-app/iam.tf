data "aws_caller_identity" "current" {}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  ssm_core_policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  service_tag         = "${var.project_name}-service"

  release_parameters = {
    for app in keys(var.deploy_repos) : app => "/service/${app}/current-release"
  }

  deploy_subjects = {
    for app, r in var.deploy_repos :
    app => "${coalesce(r.sub_prefix, "repo:${r.owner}/${r.repo}")}:ref:refs/heads/${r.branch}"
  }
}

# =======================================================
# 배포 롤 (앱별, GitHub Actions 가 OIDC 로 assume)
# =======================================================
data "aws_iam_policy_document" "deploy_trust" {
  for_each = var.deploy_repos

  statement {
    sid     = "GithubOidcAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.deploy_subjects[each.key]]
    }
  }
}

resource "aws_iam_role" "deploy" {
  for_each = var.deploy_repos

  name                 = "${var.project_name}-service-${each.key}-deploy-role"
  path                 = "${var.iam_role_path_prefix}service/"
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust[each.key].json
  permissions_boundary = var.permissions_boundary_arn

  tags = {
    Name      = "${var.project_name}-service-${each.key}-deploy-role"
    ManagedBy = "Terraform"
  }
}

data "aws_iam_policy_document" "deploy" {
  for_each = var.deploy_repos

  statement {
    sid       = "UploadReleases"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/releases/${each.key}/*"]
  }

  statement {
    sid       = "RunShellScriptDocument"
    effect    = "Allow"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ssm:${var.region}::document/AWS-RunShellScript"]
  }

  statement {
    sid       = "TargetOwnInstancesOnly"
    effect    = "Allow"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Service"
      values   = [local.service_tag]
    }

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Role"
      values   = [each.key]
    }
  }

  statement {
    sid    = "ReadCommandResult"
    effect = "Allow"
    actions = [
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "RecordCurrentRelease"
    effect    = "Allow"
    actions   = ["ssm:PutParameter"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.release_parameters[each.key]}"]
  }
}

resource "aws_iam_policy" "deploy" {
  for_each = var.deploy_repos

  name        = "${var.project_name}-service-${each.key}-deploy-policy"
  description = "Upload ${each.key} releases and run deploy command on ${each.key} instances"
  policy      = data.aws_iam_policy_document.deploy[each.key].json

  tags = {
    Name      = "${var.project_name}-service-${each.key}-deploy-policy"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "deploy" {
  for_each = var.deploy_repos

  role       = aws_iam_role.deploy[each.key].name
  policy_arn = aws_iam_policy.deploy[each.key].arn
}

# =======================================================
# EC2 신뢰 정책 (프론트·백엔드 공용)
# =======================================================
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    sid     = "AssumeRoleForServiceEC2"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# =======================================================
# 프론트 인스턴스 롤
# =======================================================
resource "aws_iam_role" "frontend" {
  name                 = "${var.project_name}-service-frontend-role"
  path                 = "${var.iam_role_path_prefix}service/"
  assume_role_policy   = data.aws_iam_policy_document.ec2_trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = {
    Name      = "${var.project_name}-service-frontend-role"
    ManagedBy = "Terraform"
  }
}

data "aws_iam_policy_document" "frontend" {
  statement {
    sid       = "ReadFrontendReleases"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/releases/frontend/*"]
  }

  statement {
    sid       = "ListFrontendReleases"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["releases/frontend/*"]
    }
  }

  statement {
    sid       = "ReadCurrentRelease"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.release_parameters["frontend"]}"]
  }
}

resource "aws_iam_policy" "frontend" {
  name        = "${var.project_name}-service-frontend-policy"
  description = "Read frontend releases and the current release parameter"
  policy      = data.aws_iam_policy_document.frontend.json

  tags = {
    Name      = "${var.project_name}-service-frontend-policy"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "frontend" {
  role       = aws_iam_role.frontend.name
  policy_arn = aws_iam_policy.frontend.arn
}

resource "aws_iam_role_policy_attachment" "frontend_ssm" {
  role       = aws_iam_role.frontend.name
  policy_arn = local.ssm_core_policy_arn
}

resource "aws_iam_instance_profile" "frontend" {
  name = "${var.project_name}-service-frontend-profile"
  role = aws_iam_role.frontend.name
}

# =======================================================
# 백엔드 인스턴스 롤
# =======================================================
resource "aws_iam_role" "backend" {
  name                 = "${var.project_name}-service-backend-role"
  path                 = "${var.iam_role_path_prefix}service/"
  assume_role_policy   = data.aws_iam_policy_document.ec2_trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = {
    Name      = "${var.project_name}-service-backend-role"
    ManagedBy = "Terraform"
  }
}

data "aws_iam_policy_document" "backend" {
  statement {
    sid       = "ReadBackendReleases"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/releases/backend/*"]
  }

  statement {
    sid       = "ListBackendReleases"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["releases/backend/*"]
    }
  }

  statement {
    sid       = "ConnectToDatabase"
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:${var.region}:${data.aws_caller_identity.current.account_id}:dbuser:${local.db_resource_id}/${local.db_iam_user}"]
  }

  statement {
    sid       = "ReadCurrentRelease"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.release_parameters["backend"]}"]
  }
}

resource "aws_iam_policy" "backend" {
  name        = "${var.project_name}-service-backend-policy"
  description = "Read backend releases and connect to RDS with IAM auth"
  policy      = data.aws_iam_policy_document.backend.json

  tags = {
    Name      = "${var.project_name}-service-backend-policy"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "backend" {
  role       = aws_iam_role.backend.name
  policy_arn = aws_iam_policy.backend.arn
}

resource "aws_iam_role_policy_attachment" "backend_ssm" {
  role       = aws_iam_role.backend.name
  policy_arn = local.ssm_core_policy_arn
}

resource "aws_iam_instance_profile" "backend" {
  name = "${var.project_name}-service-backend-profile"
  role = aws_iam_role.backend.name
}

# =======================================================
# RDS 포트 포워딩 정책 (사람용)
# =======================================================
data "aws_iam_policy_document" "db_port_forwarding" {
  statement {
    sid     = "StartDbPortForwarding"
    effect  = "Allow"
    actions = ["ssm:StartSession"]

    resources = [
      aws_instance.backend.arn,
      "arn:aws:ssm:${var.region}::document/AWS-StartPortForwardingSessionToRemoteHost",
    ]
  }

  statement {
    sid    = "ManageOwnSession"
    effect = "Allow"

    actions = [
      "ssmmessages:OpenDataChannel",
      "ssm:ResumeSession",
      "ssm:TerminateSession",
    ]

    resources = [
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:session/&{aws:username}-*",
    ]
  }
}

resource "aws_iam_policy" "db_port_forwarding" {
  name        = "${var.project_name}-service-db-port-forwarding"
  description = "Allow port forwarding to the service database through the backend instance"
  policy      = data.aws_iam_policy_document.db_port_forwarding.json

  tags = {
    Name      = "${var.project_name}-service-db-port-forwarding"
    ManagedBy = "Terraform"
  }
}
