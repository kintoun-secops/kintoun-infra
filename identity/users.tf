# =======================================================
# 팀원 IAM User
# =======================================================
resource "aws_iam_user" "member" {
  for_each = var.members

  name                 = each.key
  path                 = var.iam_path
  permissions_boundary = var.permissions_boundary_arn
  force_destroy        = var.force_destroy_users

  tags = merge(local.common_tags, { Name = each.key }, each.value.tags)
}

# =======================================================
# 그룹 소속 (사용자별 비권위적 관리 — 여기 적힌 그룹만 건드린다)
# =======================================================
resource "aws_iam_user_group_membership" "member" {
  for_each = { for name, m in var.members : name => m if length(m.groups) > 0 }

  user = aws_iam_user.member[each.key].name
  groups = [
    for g in each.value.groups :
    contains(keys(var.managed_groups), g) ? aws_iam_group.managed[g].name : data.aws_iam_group.external[g].group_name
  ]
}

# =======================================================
# 기본 자격증명 정책 연결
# =======================================================
resource "aws_iam_user_policy_attachment" "self_service" {
  for_each = var.members

  user       = aws_iam_user.member[each.key].name
  policy_arn = aws_iam_policy.self_service_credentials.arn
}

resource "aws_iam_user_policy_attachment" "require_mfa" {
  for_each = var.enforce_mfa ? var.members : {}

  user       = aws_iam_user.member[each.key].name
  policy_arn = aws_iam_policy.require_mfa[0].arn
}
