data "aws_caller_identity" "current" {}

# =======================================================
# aws login 권한 정책 (임시 자격증명 발급용)
# =======================================================
data "aws_iam_policy_document" "aws_login" {
  statement {
    sid    = "AllowLocalAWSLogin"
    effect = "Allow"

    actions = [
      "signin:CreateOAuth2Token",
      "signin:AuthorizeOAuth2Access"
    ]

    resources = [
      "arn:aws:signin:ap-northeast-2:${data.aws_caller_identity.current.account_id}:oauth2/public-client/localhost"
    ]
  }
}

resource "aws_iam_policy" "aws_login" {
  name        = "${var.project_name}-aws-login"
  description = "Allow AWS CLI login using Console for temporary credentials"
  policy      = data.aws_iam_policy_document.aws_login.json

  tags = {
    Name = "${var.project_name}-aws-login"
  }
}