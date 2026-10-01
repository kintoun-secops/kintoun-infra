# =======================================================
# 마스터 시크릿 읽기 정책 (사람용)
# =======================================================
data "aws_iam_policy_document" "master_secret_read" {
  statement {
    sid       = "ReadMasterSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.main.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_policy" "master_secret_read" {
  name        = "${var.project_name}-service-db-master-secret-read"
  description = "Read the RDS managed master password secret"
  policy      = data.aws_iam_policy_document.master_secret_read.json

  tags = {
    Name      = "${var.project_name}-service-db-master-secret-read"
    ManagedBy = "Terraform"
  }
}
