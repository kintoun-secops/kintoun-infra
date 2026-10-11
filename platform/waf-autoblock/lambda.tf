# =======================================================
# 핸들러 코드를 zip으로 패키징
# =======================================================
data "archive_file" "handler" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/lambda/handler.zip"
}

# =======================================================
# 차단 시각/만료 기록용 DynamoDB (ip -> expires_at)
# =======================================================
resource "aws_dynamodb_table" "blocks" {
  name         = "${var.project_name}-waf-autoblock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ip"

  attribute {
    name = "ip"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name      = "${var.project_name}-waf-autoblock"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# Wazuh -> Lambda 호출용 공유 토큰
# 값은 코드에 넣지 않는다. apply 후 CLI로 직접 채운다 (state에 안 남김)
# =======================================================
resource "aws_ssm_parameter" "token" {
  name  = "/${var.project_name}/waf-autoblock/token"
  type  = "SecureString"
  value = "CHANGE_ME"

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    ManagedBy = "Terraform"
  }
}

# =======================================================
# 로그 그룹 (보존 30일)
# =======================================================
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}-waf-autoblock"
  retention_in_days = 30
}

# =======================================================
# IAM: 이 IP Set / 이 테이블 / 이 파라미터만 접근 가능
# =======================================================
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-waf-autoblock-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  permissions_boundary = var.permissions_boundary_arn
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  statement {
    sid       = "WafIpSet"
    actions   = ["wafv2:GetIPSet", "wafv2:UpdateIPSet"]
    resources = [local.auto_block_ip_set.arn]
  }

  statement {
    sid       = "Table"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:Scan"]
    resources = [aws_dynamodb_table.blocks.arn]
  }

  statement {
    sid       = "Token"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.token.arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "waf-autoblock"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

# =======================================================
# Lambda 함수 (VPC 미연결, 동시 실행 1)
# =======================================================
resource "aws_lambda_function" "autoblock" {
  function_name = "${var.project_name}-waf-autoblock"
  role          = aws_iam_role.lambda.arn
  runtime       = "python3.12"
  handler       = "handler.lambda_handler"
  timeout       = 15

  filename         = data.archive_file.handler.output_path
  source_code_hash = data.archive_file.handler.output_base64sha256

  reserved_concurrent_executions = 1

  environment {
    variables = {
      TABLE_NAME   = aws_dynamodb_table.blocks.name
      IP_SET_ID    = local.auto_block_ip_set.id
      IP_SET_NAME  = local.auto_block_ip_set.name
      SCOPE        = local.auto_block_ip_set.scope
      TOKEN_PARAM  = aws_ssm_parameter.token.name
      DRY_RUN      = tostring(var.dry_run)
      TTL_HOURS    = tostring(var.ttl_hours)
      MAX_PER_HOUR = tostring(var.max_per_hour)
      ALLOWLIST    = join(",", var.allowlist)
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]

  tags = {
    ManagedBy = "Terraform"
  }
}

# =======================================================
# Wazuh가 호출할 HTTPS 주소 (인증은 핸들러의 토큰 검사)
# =======================================================
resource "aws_lambda_function_url" "autoblock" {
  function_name      = aws_lambda_function.autoblock.function_name
  authorization_type = "NONE"
}

# =======================================================
# 10분마다 만료된 IP 정리
# =======================================================
resource "aws_cloudwatch_event_rule" "cleanup" {
  name                = "${var.project_name}-waf-autoblock-cleanup"
  schedule_expression = "rate(10 minutes)"
}

resource "aws_cloudwatch_event_target" "cleanup" {
  rule = aws_cloudwatch_event_rule.cleanup.name
  arn  = aws_lambda_function.autoblock.arn
}

resource "aws_lambda_permission" "cleanup" {
  statement_id  = "AllowEventBridgeCleanup"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.autoblock.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cleanup.arn
}