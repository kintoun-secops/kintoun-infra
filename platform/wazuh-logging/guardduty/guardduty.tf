# =======================================================
# GuardDuty 감지기 활성화
# 주의: 계정+리전당 1개만 허용됨. apply 전
# aws guardduty list-detectors --region ap-northeast-2 로 기존 여부 확인할 것
# =======================================================
resource "aws_guardduty_detector" "main" {
  enable                       = true  # guardduty 활성화
  finding_publishing_frequency = "FIFTEEN_MINUTES" # 로그 보내는 시간 15분

  tags = {
    Name = "${var.project_name}-guardduty"
  }
}

# =======================================================
# GuardDuty findings 저장용 S3 버킷
# (버킷 이름 전역 유일 — 계정 ID 접미사로 충돌 방지)
# =======================================================
resource "aws_s3_bucket" "guardduty_findings" { # guarduty가 위협 탐지 결과를 여기에 파일로 쌓게 된다. s3생성
  bucket = "whs4-kintoun-guardduty-findings"

  tags = {
    Name = "${var.project_name}-guardduty-findings"
  }
}

resource "aws_s3_bucket_public_access_block" "guardduty_findings" {
  bucket                  = aws_s3_bucket.guardduty_findings.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =======================================================
# findings 버킷 버전 관리 (실수 삭제/덮어쓰기 대비)
# =======================================================
resource "aws_s3_bucket_versioning" "guardduty_findings" {
  bucket = aws_s3_bucket.guardduty_findings.id

  versioning_configuration {
    status = "Enabled"
  }
}

# =======================================================
# 오래된 버전 자동 정리 (버저닝 켜두면 계속 쌓이므로 필요)
# =======================================================
resource "aws_s3_bucket_lifecycle_configuration" "guardduty_findings" {
  bucket     = aws_s3_bucket.guardduty_findings.id
  depends_on = [aws_s3_bucket_versioning.guardduty_findings]

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"

    filter {}

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

# =======================================================
# findings 버킷 암호화용 KMS 키
# (aws_guardduty_publishing_destination 는 kms_key_arn 필수)
# =======================================================
data "aws_iam_policy_document" "guardduty_kms" {
  statement {
    sid    = "EnableRootPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"] # 알아봐야 할듯
    resources = ["*"]
  }

  statement {
    sid    = "AllowGuardDutyEncrypt"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"]
    }

    actions   = ["kms:GenerateDataKey"]
    resources = ["*"]
  }
}

resource "aws_kms_key" "guardduty_findings" {
  description             = "GuardDuty findings 버킷 암호화 키"
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.guardduty_kms.json # 위에서 만든 정책 적용하는 부분

  tags = {
    Name = "${var.project_name}-guardduty-kms"
  }
}

resource "aws_kms_alias" "guardduty_findings" {
  name          = "alias/${var.project_name}-guardduty-findings"
  target_key_id = aws_kms_key.guardduty_findings.key_id
}

# =======================================================
# GuardDuty가 버킷에 findings 를 쓸 수 있게 하는 버킷 정책
# =======================================================
data "aws_iam_policy_document" "guardduty_bucket_policy" {
  statement {
    sid    = "AllowGuardDutyPutObject" # sid 설명
    effect = "Allow" # 허락 

    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"] # 가드튜디한테 이걸 줄거다 권한을
    }

    actions   = ["s3:PutObject"] # 쓸 수 있는 권한 준다.
    resources = ["${aws_s3_bucket.guardduty_findings.arn}/*"]
  }

  statement {
    sid    = "AllowGuardDutyGetBucketLocation"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"]
    }

    actions   = ["s3:GetBucketLocation"]
    resources = [aws_s3_bucket.guardduty_findings.arn]
  }
}

resource "aws_s3_bucket_policy" "guardduty_findings" {
  bucket = aws_s3_bucket.guardduty_findings.id
  policy = data.aws_iam_policy_document.guardduty_bucket_policy.json
}

# =======================================================
# GuardDuty 감지기 -> S3 버킷 연결 (findings 내보내기 목적지)
# =======================================================
resource "aws_guardduty_publishing_destination" "main" {
  detector_id     = aws_guardduty_detector.main.id
  destination_arn = aws_s3_bucket.guardduty_findings.arn
  kms_key_arn     = aws_kms_key.guardduty_findings.arn

  depends_on = [aws_s3_bucket_policy.guardduty_findings]
}