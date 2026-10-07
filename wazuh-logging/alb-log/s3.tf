data "aws_caller_identity" "current" {}

locals {
  alb_log_object_prefix = "AWSLogs/${data.aws_caller_identity.current.account_id}/"
}

# =======================================================
# ALB Logs 저장용 S3 Bucket 생성
# =======================================================
resource "aws_s3_bucket" "alb_logs" {
  bucket        = var.alb_log_bucket_name
  force_destroy = false

  tags = {
    Name      = "${var.project_name}-alb-logs"
    ManagedBy = "Terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # ALB 로그를 S3에 저장하는 방식은 KMS 암호화를 지원하지 않음
    }
  }
}

# =======================================================
# ALB Logs를 수집하고 저장하기 위한 S3 Bucket 정책 생성
# =======================================================
data "aws_iam_policy_document" "alb_log_delivery" {
  statement {
    sid     = "AllowALBLogDelivery"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
    resources = [
      "${aws_s3_bucket.alb_logs.arn}/${local.alb_log_object_prefix}*"
    ]
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = data.aws_iam_policy_document.alb_log_delivery.json
}

# =======================================================
# ALB Logs 버킷 Lifecycle 설정
# =======================================================
resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  depends_on = [aws_s3_bucket_versioning.alb_logs]
  rule {
    id     = "expire-alb-access-logs"
    status = "Enabled"

    filter {
      prefix = local.alb_log_object_prefix
    }

    expiration {
      days = var.alb_log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
  rule {
    id     = "cleanup-delete-markers-and-uploads"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}