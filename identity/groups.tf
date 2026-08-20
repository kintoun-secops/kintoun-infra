# =======================================================
# 이 모듈이 만드는 IAM Group
# 기존 콘솔 그룹(WHS4_Infra 등)은 여기 넣지 않는다 — 이름만 참조해 소속만 관리한다.
# =======================================================
resource "aws_iam_group" "managed" {
  for_each = local.managed_groups

  name = each.key
  path = var.iam_path

  lifecycle {
    precondition {
      condition     = alltrue([for k in keys(coalesce(local.managed_groups_file[each.key], {})) : k == "policy_arns"])
      error_message = "groups.yaml 항목에 허용되지 않는 필드가 있습니다 (허용: policy_arns)."
    }
  }
}

locals {
  managed_group_attachments = {
    for pair in flatten([
      for name, g in local.managed_groups : [
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
