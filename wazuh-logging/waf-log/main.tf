data "aws_caller_identity" "current" {}
# =======================================================
# WAF 로그 저장용 S3 버킷 + KMS 암호화
# (공통 log-bucket 모듈 사용 — GuardDuty와 동일한 암호화 기준 적용)
# =======================================================
module "waf_logs_bucket" {
  source            = "../../modules/log-bucket"
  bucket_name       = "aws-waf-logs-whs4-kintoun-${data.aws_caller_identity.current.account_id}"
  kms_description   = "WAF 로그 버킷 암호화 키"
  service_principal = "delivery.logs.amazonaws.com"
  account_id        = data.aws_caller_identity.current.account_id
  resource_arn      = "arn:aws:logs:ap-northeast-2:${data.aws_caller_identity.current.account_id}:*"
  resource_arn_test = "ArnLike"   

  tags = {
    Name = "aws-waf-logs-${var.project_name}"
  }
}

# =======================================================
# WAF -> S3 로깅 활성화
# 이번 PR 범위 아님: platform/victim의 waf_web_acl_arn output과
# state 반영이 선행되어야 활성화 가능. 후속 PR에서 연결 예정.
# =======================================================
/*
resource "aws_wafv2_web_acl_logging_configuration" "main" {
  resource_arn            = local.waf_web_acl_arn
  log_destination_configs = [module.waf_logs_bucket.bucket_arn]

  depends_on = [aws_s3_bucket_policy.waf_logs]
}
*/

# 경로에 계정 ID를 넣은 것만으로는 출처를 제한하지 못해
# SourceAccount/SourceArn 조건 추가. 형식은 AWS WAF 로깅 공식 정책 예시 기준
# (https://docs.aws.amazon.com/waf/latest/developerguide/logging-s3.html)
data "aws_iam_policy_document" "waf_logs_bucket_policy" {
  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${module.waf_logs_bucket.bucket_arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:ap-northeast-2:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  statement {
    sid    = "AWSLogDeliveryAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [module.waf_logs_bucket.bucket_arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:ap-northeast-2:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_s3_bucket_policy" "waf_logs" {
  bucket = module.waf_logs_bucket.bucket_id
  policy = data.aws_iam_policy_document.waf_logs_bucket_policy.json
}

# =======================================================
# wazuh_role에 WAF 로그 읽기 권한 추가
# (platform/wazuh 의 기존 wazuh_role 재사용, 새 역할 안 만듦)
# =======================================================
data "aws_iam_policy_document" "wazuh_waf_read" {
  statement {
    sid    = "ReadWafLogs"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]

    resources = [
      module.waf_logs_bucket.bucket_arn,
      "${module.waf_logs_bucket.bucket_arn}/*"
    ]
  }
}

resource "aws_iam_policy" "wazuh_waf_read" {
  name        = "${var.project_name}-wazuh-waf-read"
  description = "Allow Wazuh Manager EC2 to read WAF logs from S3"
  policy      = data.aws_iam_policy_document.wazuh_waf_read.json

  tags = {
    Name      = "${var.project_name}-wazuh-waf-read"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "wazuh_waf_read" {
  role       = local.wazuh_role
  policy_arn = aws_iam_policy.wazuh_waf_read.arn
}