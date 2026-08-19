# 팀원 명단 예시. 실제 명단은 variables.tf 의 members 기본값에 둔다
# (*.tfvars 는 .gitignore 대상이라 CI 가 읽지 못한다).
#
#   terraform plan -var-file=example.tfvars

members = {
  hong = {
    groups = ["WHS4_Infra"]
    tags   = { Owner = "hong@example.com" }
  }
  kim = {
    groups = ["WHS4_Attack", "WHS4_SIEM_Detect"]
  }
}

managed_groups = {
  KintounReadOnly = {
    policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  }
}

enforce_mfa = true
