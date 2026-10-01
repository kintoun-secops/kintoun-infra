data "aws_caller_identity" "current" {}
# =======================================================
# VPC Flow Logs 저장용 S3 Bucket 생성
# =======================================================
module "vpc_flow_logs_bucket" {
  source            = "../../modules/log-bucket"
  bucket_name       = var.vpc_flow_bucket_name
  kms_description   = "VPC Flow Logs 버킷 암호화 키"
  service_principal = "delivery.logs.amazonaws.com"
  account_id        = data.aws_caller_identity.current.account_id
  resource_arn      = "arn:aws:logs:ap-northeast-2:${data.aws_caller_identity.current.account_id}:*"
  resource_arn_test = "ArnLike"

  tags = {
    Name      = "${var.project_name}-vpc-flow-logs-bucket"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# VPC Flow Logs를 수집하고 저장하기 위한 S3 Bucket 정책 생성
# =======================================================
data "aws_iam_policy_document" "vpc_flow_logs_bucket" {
  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions = [
      "s3:PutObject"
    ]
    resources = [
      "${module.vpc_flow_logs_bucket.bucket_arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values = [
        data.aws_caller_identity.current.account_id
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values = [
        "bucket-owner-full-control"
      ]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        "arn:aws:logs:ap-northeast-2:${data.aws_caller_identity.current.account_id}:*"
      ]
    }

  }
  statement {
    sid    = "AWSlogDeliveryAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions = ["s3:GetBucketAcl"]
    resources = [
      module.vpc_flow_logs_bucket.bucket_arn
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values = [
        data.aws_caller_identity.current.account_id
      ]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        "arn:aws:logs:ap-northeast-2:${data.aws_caller_identity.current.account_id}:*"
      ]
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
      module.vpc_flow_logs_bucket.bucket_arn,
      "${module.vpc_flow_logs_bucket.bucket_arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# =======================================================
# VPC Flow Logs를 수집하고 저장하기 위한 S3 Bucket 정책 연결
# =======================================================
resource "aws_s3_bucket_policy" "vpc_flow_logs_bucket" {
  bucket = module.vpc_flow_logs_bucket.bucket_id
  policy = data.aws_iam_policy_document.vpc_flow_logs_bucket.json
}