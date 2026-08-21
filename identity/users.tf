resource "aws_iam_user" "member" {
  for_each = local.members

  name                 = each.key
  path                 = var.iam_path
  permissions_boundary = var.permissions_boundary_arn
  force_destroy        = var.force_destroy_users

  tags = merge(local.common_tags, { Name = each.key }, each.value.tags)

  lifecycle {
    precondition {
      condition     = can(regex("^[a-zA-Z0-9._-]{1,64}$", each.key))
      error_message = "members.yaml 의 키는 IAM User 이름 규칙(영숫자 . _ - , 64자 이내)을 따라야 합니다."
    }

    # yamldecode 는 무타입이라 오타 필드가 조용히 무시된다 — 여기서 잡는다.
    precondition {
      condition     = alltrue([for k in keys(coalesce(local.members_file[each.key], {})) : contains(["groups", "tags"], k)])
      error_message = "members.yaml 항목에 허용되지 않는 필드가 있습니다 (허용: groups, tags)."
    }
  }
}

# 사용자 단위 비권위적 관리다 — 여기 적힌 그룹만 건드린다.
resource "aws_iam_user_group_membership" "member" {
  for_each = { for name, m in local.members : name => m if length(m.groups) > 0 }

  user = aws_iam_user.member[each.key].name
  groups = [
    for g in each.value.groups :
    contains(keys(local.managed_groups), g) ? aws_iam_group.managed[g].name : data.aws_iam_group.external[g].group_name
  ]
}

resource "aws_iam_user_policy_attachment" "self_service" {
  for_each = local.members

  user       = aws_iam_user.member[each.key].name
  policy_arn = aws_iam_policy.self_service_credentials.arn
}

resource "aws_iam_user_policy_attachment" "require_mfa" {
  for_each = var.enforce_mfa ? local.members : {}

  user       = aws_iam_user.member[each.key].name
  policy_arn = aws_iam_policy.require_mfa[0].arn
}
