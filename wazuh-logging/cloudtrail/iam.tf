# =======================================================
# Read CloudTrail Logs from S3 Bucket for Wazuh (권한정책)
# =======================================================
data "aws_iam_policy_document" "cloudtrail_logging_wazuh" {
  statement {
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      "arn:aws:s3:::whs4-kintoun-cloudtrail-logs"
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
      "arn:aws:s3:::whs4-kintoun-cloudtrail-logs/AWSLogs/446413909569/*"
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

resource "aws_iam_policy" "cloudtrail_logging_wazuh" {
  name        = "${var.project_name}-cloudtrail-logging-for-wazuh"
  description = "Read CloudTrail Logs from S3 Bucket for Wazuh"
  policy      = data.aws_iam_policy_document.cloudtrail_logging_wazuh.json

  tags = {
    Name     = "${var.project_name}-cloudtrail-logging-for-wazuh"
    ManageBy = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "cloudtrail_logging_wazuh" {
  role       = local.wazuh_role
  policy_arn = aws_iam_policy.cloudtrail_logging_wazuh.arn
}