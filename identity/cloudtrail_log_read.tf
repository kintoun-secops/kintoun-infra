# CloudTrail 이상탐지용 임시 읽기 권한 (요청: 박진혁, 2026-10-05)
# 연결은 groups.yaml 의 WHS4_CloudTrail_LogRead 그룹으로 함
# 회수: groups.yaml/members.yaml 에서 그룹 먼저 제거 → 이후 이 파일 삭제

locals {
  ct_bucket = "whs4-kintoun-cloudtrail-logs"
  ct_prefix = "AWSLogs/446413909569/CloudTrail"
  ct_expiry = "2026-11-30T23:59:59Z"
}

data "aws_iam_policy_document" "cloudtrail_log_read" {
  statement {
    sid       = "BucketLocation"
    actions   = ["s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${local.ct_bucket}"]
    condition {
      test     = "DateLessThan"
      variable = "aws:CurrentTime"
      values   = [local.ct_expiry]
    }
  }

  statement {
    sid       = "ListCloudTrailPrefix"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.ct_bucket}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${local.ct_prefix}/*"]
    }
    condition {
      test     = "DateLessThan"
      variable = "aws:CurrentTime"
      values   = [local.ct_expiry]
    }
  }

  statement {
    sid       = "ReadCloudTrailLogs"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${local.ct_bucket}/${local.ct_prefix}/*"]
    condition {
      test     = "DateLessThan"
      variable = "aws:CurrentTime"
      values   = [local.ct_expiry]
    }
  }
}

resource "aws_iam_policy" "cloudtrail_log_read" {
  name        = "TempCloudTrailLogRead"
  path        = var.iam_path
  description = "CloudTrail log read-only for anomaly detection assignment (expires ${local.ct_expiry})"
  policy      = data.aws_iam_policy_document.cloudtrail_log_read.json
}
