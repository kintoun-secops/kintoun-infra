# state 는 identity/terraform.tfstate, apply 는 main 머지 후 CI 가 수행한다.
# 명단은 members.yaml / groups.yaml 에 둔다 — 이 폴더의 tf 파일은 로직만 다룬다.
#
# 다루는 것   : IAM User, 그룹 소속, 기본 자격증명 정책(셀프 서비스 + MFA 강제)
# 다루지 않는 것:
#   - 콘솔 로그인 비밀번호 (state 에 평문이 남으므로 최초 발급은 콘솔에서 수동)
#   - 액세스 키 (aws login 으로 임시 자격증명을 쓴다. platform/README.md 참고)
#   - 기존 콘솔 그룹(WHS4_*) 자체와 거기 붙는 정책 (platform/iam.tf 소관)

data "aws_caller_identity" "current" {}

locals {
  # 빈 문서(--- 만 있는 경우)는 null 로 디코드되므로 coalesce 로 빈 명단 취급한다.
  # 필드 스키마 검증은 users.tf / groups.tf 의 precondition 이 한다.
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

  # 명단에서 참조한 그룹 중 이 모듈이 만들지 않는 것 = 이미 존재하는 콘솔 그룹.
  # 데이터 소스로 조회해 오타를 plan 단계에서 잡는다.
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
