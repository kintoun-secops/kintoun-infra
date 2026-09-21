# =======================================================
# Read VPC Flow Logs from S3 Bucket for Wazuh (권한정책)
# =======================================================
data "aws_iam_policy_document" "vpc_flow_logging_wazuh" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:DescribeFlowLogs"]
    resources = ["*"] # DescribeFlowLogs Action은 리소스 수준 권한을 지원하지 않아 "*" 사용
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
    actions = ["s3:ListBucket"]
    resources = [
      module.vpc_flow_logs_bucket.bucket_arn
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
      "${module.vpc_flow_logs_bucket.bucket_arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
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
      module.vpc_flow_logs_bucket.kms_key_arn
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

resource "aws_iam_policy" "vpc_flow_logging_wazuh" {
  name        = "${var.project_name}-vpc-flow-logging-wazuh"
  description = "Read VPC Flow Logs from S3 Bucket for Wazuh"
  policy      = data.aws_iam_policy_document.vpc_flow_logging_wazuh.json

  tags = {
    Name      = "${var.project_name}-vpc-flow-logging-wazuh"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "vpc_flow_logging_wazuh" {
  role       = local.wazuh_role
  policy_arn = aws_iam_policy.vpc_flow_logging_wazuh.arn
}