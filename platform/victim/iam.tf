# =======================================================
# IAM Role 생성 for Victim EC2 (신뢰 정책 + IAM Role)
# =======================================================
data "aws_iam_policy_document" "victim_role" {
  statement {
    sid     = "AssumeRoleForVictimEC2"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "victim_role" {
  name               = "${var.project_name}-victim-role"
  path               = "${var.iam_role_path_prefix}victim/"
  assume_role_policy = data.aws_iam_policy_document.victim_role.json

  permissions_boundary = var.permissions_boundary_arn

  tags = {
    Name      = "${var.project_name}-victim-role"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# S3 Bucket Access 정책 for Victim EC2 (권한 정책)
# =======================================================
data "aws_iam_policy_document" "s3_access" {
  statement {
    sid     = "S3ListVictimBucket"
    effect  = "Allow"
    actions = ["s3:ListBucket"] # 지정한 버킷 내부의 객체 키 목록 조회
    resources = [
      aws_s3_bucket.victim.arn
    ]
    condition {
      test     = "ArnEquals"
      variable = "ec2:SourceInstanceARN"
      values = [
        aws_instance.victim_ec2.arn
      ]
    }
  }
  statement {
    sid       = "S3ListAccountBuckets"
    effect    = "Allow"
    actions   = ["s3:ListAllMyBuckets"] # aws s3 ls 가능(계정 내 모든 버킷 이름 목록 조회)
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "ec2:SourceInstanceARN"
      values = [
        aws_instance.victim_ec2.arn
      ]
    }
  }
  statement {
    sid     = "S3GetVictimObjects"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.victim.arn}/*"
    ]
    condition {
      test     = "ArnEquals"
      variable = "ec2:SourceInstanceARN"
      values = [
        aws_instance.victim_ec2.arn
      ]
    }
  }
}

resource "aws_iam_policy" "s3_access" {
  name        = "${var.project_name}-s3-access-policy-for-victim-ec2"
  description = "Allow S3 Read for Victim EC2"
  policy      = data.aws_iam_policy_document.s3_access.json

  tags = {
    Name      = "${var.project_name}-s3-access-policy-for-victim-ec2"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# S3 Bucket Access 권한 정책 Victim EC2 Role에 연결
# =======================================================
resource "aws_iam_role_policy_attachment" "s3_access" {
  role       = aws_iam_role.victim_role.name
  policy_arn = aws_iam_policy.s3_access.arn
}

# =======================================================
# Victim EC2에 IAM Role 연결을 위한 Profile 생성
# =======================================================
resource "aws_iam_instance_profile" "victim_ec2_profile" {
  name = "${var.project_name}-victim-ec2-profile"
  role = aws_iam_role.victim_role.name
}

# =======================================================
# SSM 서비스 정책 for Victim EC2(서버 관리용)
# =======================================================
resource "aws_iam_role_policy_attachment" "ssm_service" {
  role       = aws_iam_role.victim_role.name
  policy_arn = local.ssm_policy_arn
}

# =======================================================
# Victim 서버 관리자용 정책 (Shell 접속)
# =======================================================
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "victim_shell_access" {
  statement {
    sid     = "StartVictimShellSession"
    effect  = "Allow"
    actions = ["ssm:StartSession"]
    resources = [
      aws_instance.victim_ec2.arn,
      "arn:aws:ssm:ap-northeast-2:${data.aws_caller_identity.current.account_id}:document/SSM-SessionManagerRunShell"
    ]
  }
}

resource "aws_iam_policy" "victim_shell_access" {
  name        = "${var.project_name}-victim-shell-access"
  description = "Allow Shell Access to Victim EC2"
  policy      = data.aws_iam_policy_document.victim_shell_access.json

  tags = {
    Name      = "${var.project_name}-victim-shell-access"
    ManagedBy = "Terraform"
  }
}