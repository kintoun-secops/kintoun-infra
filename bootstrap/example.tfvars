# 사용법: 값을 채운 뒤
#   terraform plan  -var-file=example.tfvars
#   terraform apply -var-file=example.tfvars

github_org = "kintoun-secops" # 필수 — 팀 GitHub 조직 이름

github_repo       = "kintoun-infra"
state_bucket_name = "kintoun-tfstate"

# 팀 IAM 설계에 경계 강제가 걸려 있다면 필수. 콘솔에서 정책 이름 확인 후 기입.
permissions_boundary_arn = "arn:aws:iam::446413909569:policy/KintounGuardrailBoundary"

github_sub_prefix = "repo:kintoun-secops@312961303/kintoun-infra@1336279993"
