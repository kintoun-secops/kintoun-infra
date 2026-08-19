# =======================================================
# 이 모듈이 만드는 IAM Group
# 기존 콘솔 그룹(WHS4_Infra 등)은 여기 넣지 않는다 — 이름만 참조해 소속만 관리한다.
# =======================================================
resource "aws_iam_group" "managed" {
  for_each = var.managed_groups

  name = each.key
  path = var.iam_path
}

locals {
  managed_group_attachments = {
    for pair in flatten([
      for name, g in var.managed_groups : [
        for arn in g.policy_arns : { key = "${name}|${arn}", group = name, policy_arn = arn }
      ]
    ]) : pair.key => pair
  }
}

resource "aws_iam_group_policy_attachment" "managed" {
  for_each = local.managed_group_attachments

  group      = aws_iam_group.managed[each.value.group].name
  policy_arn = each.value.policy_arn
}
