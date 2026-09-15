# =======================================================
# GuardDuty 감지기 활성화
# 주의: 계정+리전당 1개만 허용됨. apply 전
# aws guardduty list-detectors --region ap-northeast-2 로 기존 여부 확인할 것
# =======================================================
resource "aws_guardduty_detector" "main" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = {
    Name = "${var.project_name}-guardduty"
  }
}

# =======================================================
# GuardDuty findings 저장용 S3 버킷 + KMS 암호화
# (공통 log-bucket 모듈 사용 — WAF 로그 버킷과 동일한 암호화 기준 적용)
# =======================================================
module "guardduty_findings_bucket" {
  source            = "../../modules/log-bucket"
  bucket_name       = "whs4-kintoun-guardduty-findings-${data.aws_caller_identity.current.account_id}"
  kms_description   = "GuardDuty findings 버킷 암호화 키"
  service_principal = "guardduty.amazonaws.com"
  account_id        = data.aws_caller_identity.current.account_id

  tags = {
    Name = "${var.project_name}-guardduty-findings"
  }
}

# =======================================================
# GuardDuty가 버킷에 findings 를 쓸 수 있게 하는 버킷 정책
# =======================================================
data "aws_iam_policy_document" "guardduty_bucket_policy" {
  statement {
    sid    = "AllowGuardDutyPutObject"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${module.guardduty_findings_bucket.bucket_arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_guardduty_detector.main.arn]
    }
  }

  statement {
    sid    = "AllowGuardDutyGetBucketLocation"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"]
    }

    actions   = ["s3:GetBucketLocation"]
    resources = [module.guardduty_findings_bucket.bucket_arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_guardduty_detector.main.arn]
    }
  }

  statement {
    sid    = "DenyGuardDutyUploadWithoutKms"
    effect = "Deny"

    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${module.guardduty_findings_bucket.bucket_arn}/*"]

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  statement {
    sid    = "DenyGuardDutyUploadWithWrongKmsKey"
    effect = "Deny"

    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${module.guardduty_findings_bucket.bucket_arn}/*"]

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [module.guardduty_findings_bucket.kms_key_arn]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      module.guardduty_findings_bucket.bucket_arn,
      "${module.guardduty_findings_bucket.bucket_arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "guardduty_findings" {
  bucket = module.guardduty_findings_bucket.bucket_id
  policy = data.aws_iam_policy_document.guardduty_bucket_policy.json
}

# =======================================================
# GuardDuty 감지기 -> S3 버킷 연결 (findings 내보내기 목적지)
# =======================================================
resource "aws_guardduty_publishing_destination" "main" {
  detector_id     = aws_guardduty_detector.main.id
  destination_arn = module.guardduty_findings_bucket.bucket_arn
  kms_key_arn     = module.guardduty_findings_bucket.kms_key_arn

  depends_on = [aws_s3_bucket_policy.guardduty_findings]
}