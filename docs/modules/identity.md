# Identity

`identity/`는 팀원 IAM User와 그룹 소속, 자격증명 기본 정책을 관리한다.
state key는 `identity/terraform.tfstate`다.

| 관리하는 것 | 다른 절차로 관리하는 것 |
| --- | --- |
| IAM User 생성·삭제, 권한 경계와 태그 | 콘솔 로그인 프로필과 초기 비밀번호 |
| 선언한 그룹 생성과 정책 연결 | 장기 액세스 키 발급 |
| 사용자별 그룹 소속 | bootstrap의 CI 역할과 platform의 서비스 역할 |
| 셀프 서비스 자격증명·MFA 강제 정책 | 기존 외부 그룹의 생성과 정책 |

## 명단과 정책 모델

`members.yaml`의 키가 사용자 이름이다. `groups`와 `tags`만 허용하며
사용자 이름은 영숫자·점·밑줄·하이픈, 최대 64자로 검증한다.

```yaml
hong:
  groups: [KintounReadOnly]
  tags:
    Owner: hong@example.com
```

`groups.yaml`에 선언한 그룹은 이 루트가 만들고 `policy_arns`를 연결한다.
명단에서 참조하지만 선언하지 않은 그룹은 AWS에서 조회하므로 미리 존재해야 한다.

```yaml
KintounReadOnly:
  policy_arns:
    - arn:aws:iam::aws:policy/ReadOnlyAccess
```

그룹으로 업무 권한을 부여하고 사용자에게는 자격증명 기본 정책을 직접 연결한다.
사용자 그룹 소속은 `aws_iam_user_group_membership`으로 관리하므로, 코드 밖에서
추가한 그룹 연결까지 모두 정리한다고 가정하지 않는다. 권한 회수 때는 실제 소속을 확인한다.

## 주요 입력과 출력

| 입력 | 기본값과 영향 |
| --- | --- |
| `project_name` | `kintoun-secops-infra`. 태그·정책 이름에 사용 |
| `permissions_boundary_arn` | 모든 사용자의 권한 상한 |
| `iam_path` | `/`. 변경 시 자원별 plan과 실제 ARN을 확인 |
| `enforce_mfa` | `true`. MFA 미인증 세션에 등록·비밀번호 변경 등 예외 외 동작 거부 |
| `force_destroy_users` | `true`. 사용자 삭제 때 로그인 프로필·키·MFA도 정리 |

출력은 `member_arns`, `member_groups`, `managed_group_arns`,
`self_service_policy_arn`, `require_mfa_policy_arn`이다.
`member_groups`는 명단에 선언한 소속을 보여 주며 외부에서 추가한 전체 소속을 조회한 값은 아니다.
MFA 강제를 끄면 `require_mfa_policy_arn`은 `null`이다.

## 운영 절차

- [팀원 추가](../runbooks/add-user.md): 명단 등록, import, 콘솔 액세스와 MFA 설정
- [권한 및 그룹 변경](../runbooks/change-access.md): 그룹·정책 변경, 권한 회수, 사용자 제거
- [Terraform CI](../ci.md): IAM 자문과 차단형 가드레일의 차이
