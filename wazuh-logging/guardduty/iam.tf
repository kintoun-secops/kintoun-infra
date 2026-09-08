# =======================================================
# Read GuardDuty Findings from S3 Bucket for Wazuh (권한정책)
# =======================================================
data "aws_iam_policy_document" "guardduty_logging_wazuh" {
  statement {
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      aws_s3_bucket.guardduty_findings.arn
    ]
    condition {
      test     = "ArnEquals"
      variable = "ec2:SourceInstanceARN"
      values = [
        local.wazuh_ec2_arn
      ]
    }
  }

  statement {
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.guardduty_findings.arn}/*"
    ]
    condition {
      test     = "ArnEquals"
      variable = "ec2:SourceInstanceARN"
      values = [
        local.wazuh_ec2_arn
      ]
    }
  }

  statement {
    effect  = "Allow"
    actions = ["kms:Decrypt"]
    resources = [
      aws_kms_key.guardduty_findings.arn
    ]
    condition {
      test     = "ArnEquals"
      variable = "ec2:SourceInstanceARN"
      values = [
        local.wazuh_ec2_arn
      ]
    }
  }
}

resource "aws_iam_policy" "guardduty_logging_wazuh" {
  name        = "${var.project_name}-guardduty-logging-for-wazuh"
  description = "Read GuardDuty Findings from S3 Bucket for Wazuh"
  policy      = data.aws_iam_policy_document.guardduty_logging_wazuh.json

  tags = {
    Name     = "${var.project_name}-guardduty-logging-for-wazuh"
    ManageBy = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "guardduty_logging_wazuh" {
  role       = local.wazuh_role
  policy_arn = aws_iam_policy.guardduty_logging_wazuh.arn
}