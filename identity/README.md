# identity — 팀원 IAM

사람 계정(IAM User)과 그룹 소속을 코드로 관리하는 루트 모듈. state 는
`identity/terraform.tfstate`, apply 는 main 머지 후 CI 가 수행한다.

## 경계

| 다루는 것 | 다루지 않는 것 |
| --- | --- |
| IAM User 생성·삭제 | 콘솔 로그인 비밀번호 (state 평문 노출) |
| 그룹 소속 | 액세스 키 발급 (`aws login` 임시 자격증명 사용) |
| 셀프 서비스 자격증명 정책 | 기존 콘솔 그룹 `WHS4_*` 자체 및 거기 붙는 정책 → `platform/iam.tf` |
| MFA 강제 정책 | CI 롤 → `bootstrap/oidc.tf` |

## 팀원 추가

`variables.tf` 의 `members` 기본값에 항목을 넣고 PR 을 연다.
`*.tfvars` 는 `.gitignore` 대상이라 CI 가 읽지 못하므로, 실제 명단은
변수 기본값에 둔다 (`example.tfvars` 는 로컬 실험용 형식 예시).

```hcl
variable "members" {
  default = {
    hong = {
      groups = ["WHS4_Infra"]
      tags   = { Owner = "hong@example.com" }
    }
  }
}
```

- 키가 곧 IAM User 이름이다.
- `groups` 에 적은 이름 중 `managed_groups` 에 없는 것은 **이미 존재하는 그룹**으로
  간주해 데이터 소스로 조회한다. 오타는 plan 단계에서 깨진다.
- 소속 관리는 사용자 단위 비권위적(`aws_iam_user_group_membership`)이다.
  여기 안 적은 그룹의 다른 멤버는 건드리지 않는다.

새 그룹까지 만들려면 `managed_groups` 를 쓴다.

```hcl
managed_groups = {
  KintounReadOnly = { policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"] }
}
```

## 팀원 이탈

`members` 에서 키를 지우면 apply 가 사용자를 삭제한다.
`force_destroy_users = true` (기본) 이므로 로그인 프로필·액세스 키·MFA 디바이스도
함께 정리된다. 감사 기록 보존이 필요하면 삭제 전에 CloudTrail 을 확보할 것.

## 가입한 팀원이 처음 해야 할 일

1. 관리자가 콘솔에서 최초 비밀번호를 발급한다 (이 모듈은 비밀번호를 만들지 않는다).
2. 콘솔 로그인 → MFA 등록. `enforce_mfa = true` 인 동안에는 MFA 등록과
   비밀번호 변경 외의 모든 동작이 Deny 된다.
3. MFA 로 재로그인 후 `aws login` 으로 CLI 임시 자격증명을 받는다
   (`platform/README.md` 참고).

## 주의

- 모든 User 에 `permissions_boundary_arn` 이 붙는다. 경계 정책이 허용하지 않는
  권한은 그룹 정책으로 줘도 실효되지 않는다.
- `iam_path` 를 바꾸면 User·Group·정책이 **재생성**된다 (IAM 은 경로 변경을
  in-place 로 지원하지 않는다). 시작할 때 정하고 그대로 둔다.
- 콘솔에서 이미 만든 사용자를 편입할 때는 `import` 블록을 쓴다.

```hcl
import {
  to = aws_iam_user.member["hong"]
  id = "hong"
}
```
