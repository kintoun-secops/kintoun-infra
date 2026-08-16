# 원격 state 버킷 세트 (WBS 2130)
# DynamoDB 없음 — 잠금은 backend 의 use_lockfile(S3 조건부 쓰기)이 담당한다.

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  lifecycle {
    # state 버킷이 destroy 에 쓸려 나가는 사고 방지
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# .tflock 은 잠글 때 생성되고 풀 때 삭제된다. 버저닝 버킷에서 "삭제"는
# delete marker + noncurrent 버전을 남기므로, 치우는 규칙이 없으면
# plan/apply 마다 쓰레기가 쌓인다 (2130 DoD).
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket     = aws_s3_bucket.tfstate.id
  depends_on = [aws_s3_bucket_versioning.tfstate]

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"

    filter {}

    # 과거 state 복구 가능 창 = 30일. 팀 합의로 조정 가능.
    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
