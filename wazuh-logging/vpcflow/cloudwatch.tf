# =======================================================
# Cloudwatch 로그 그룹 생성
# =======================================================
resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/aws/vpc-flow-logs/${var.project_name}/service"
  retention_in_days = 7

  tags = {
    ManagedBy = "Terraform"
  }
}

# =======================================================
# VPC Flow logs 서비스용 IAM Role 생성
# =======================================================
data "aws_iam_policy_document" "vpc_flow_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        "arn:aws:ec2:ap-northeast-2:${data.aws_caller_identity.current.account_id}:vpc-flow-log/*"
      ]
    }
  }
}

resource "aws_iam_role" "vpc_flow_cloudwatch" {
  name               = "${var.project_name}-vpc-flow-cloudwatch"
  path               = "${var.iam_role_path_prefix}vpc-flow/"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_assume_role.json

  permissions_boundary = var.permissions_boundary_arn
}

# =======================================================
# 지정 로그 그룹의 스트림 생성, 기록 권한 정책
# =======================================================
data "aws_iam_policy_document" "vpc_flow_cloudwatch" {
  statement {
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:DescribeLogStreams",
      "logs:CreateLogGroup"
    ]
    resources = [aws_cloudwatch_log_group.vpc_flow.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.vpc_flow.arn}:*"]
  }
}

resource "aws_iam_role_policy" "vpc_flow_cloudwatch" {
  name   = "${var.project_name}-vpc-flow-cloudwatch"
  role   = aws_iam_role.vpc_flow_cloudwatch.name
  policy = data.aws_iam_policy_document.vpc_flow_cloudwatch.json
}

# =======================================================
# VPC Flow Logs -> CloudWatch 스트림 생성
# =======================================================
resource "aws_flow_log" "service_subnet_cloudwatch" {
  for_each = local.network

  subnet_id    = each.value
  traffic_type = "ALL"

  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow.arn
  iam_role_arn         = aws_iam_role.vpc_flow_cloudwatch.arn

  log_format = local.vpc_flow_log_format

  depends_on = [
    aws_iam_role_policy.vpc_flow_cloudwatch
  ]

  tags = {
    Name      = "${var.project_name}-cloudwatch-flow-${each.key}"
    SubentId  = each.value
    ManagedBy = "Terraform"
  }
}