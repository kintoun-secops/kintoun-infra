# state 는 identity/terraform.tfstate, apply 는 main 머지 후 CI 가 수행한다.
# 명단은 members.yaml / groups.yaml 에 둔다.

data "aws_caller_identity" "current" {}

locals {
  # 빈 문서는 null 로 디코드되므로 coalesce 로 빈 명단 취급한다.
  members_file        = coalesce(yamldecode(file("${path.module}/members.yaml")), {})
  managed_groups_file = coalesce(yamldecode(file("${path.module}/groups.yaml")), {})

  members = {
    for name, m in local.members_file : name => {
      groups = toset(try(m.groups, []))
      tags   = try(m.tags, {})
    }
  }

  managed_groups = {
    for name, g in local.managed_groups_file : name => {
      policy_arns = toset(try(g.policy_arns, []))
    }
  }

  # groups.yaml 에 없는 그룹 이름은 AWS 에서 조회한다 — 오타는 plan 에서 깨진다.
  referenced_groups = toset(flatten([for _, m in local.members : tolist(m.groups)]))
  external_groups   = setsubtract(local.referenced_groups, toset(keys(local.managed_groups)))

  common_tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
    Module    = "identity"
  }
}

data "aws_iam_group" "external" {
  for_each   = local.external_groups
  group_name = each.value
}
