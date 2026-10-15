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
  force_destroy     = true

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

