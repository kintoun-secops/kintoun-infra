# identity — 팀원 IAM

사람 계정(IAM User)과 그룹 소속을 코드로 관리하는 루트 모듈. state 는
`identity/terraform.tfstate`, apply 는 main 머지 후 CI 가 수행한다.

## 경계

| 다루는 것 | 다루지 않는 것 |
| --- | --- |
| IAM User 생성·삭제 | 콘솔 로그인 비밀번호 (state 평문 노출) |
| 그룹 소속 | 액세스 키 발급 (`aws login` 임시 자격증명 사용) |
| 셀프 서비스 자격증명 정책 | CI 롤 → `bootstrap/oidc.tf` |
| MFA 강제 정책 | 액세스 키 발급 (`aws login` 임시 자격증명 사용) |

## 작업 절차

| 하려는 일 | 문서 |
| --- | --- |
| 새 팀원 IAM 사용자 추가, 콘솔 액세스 활성화, 초기 MFA 설정, 기존 사용자 가져오기 | [docs/add-user.md](docs/add-user.md) |
| 그룹 소속 변경, 그룹 정책 변경, MFA 적용 범위 변경, 사용자 제거 | [docs/change-access.md](docs/change-access.md) |

명단은 [`members.yaml`](members.yaml)(사용자)과 [`groups.yaml`](groups.yaml)(새로
만들 그룹)에 둔다. tf 파일은 로직만 다루며, 명단 스키마는 plan 단계의 precondition 이
검증한다.

```yaml
# members.yaml
hong:
  groups: [TeamInfra]

# groups.yaml
KintounReadOnly:
  policy_arns:
    - arn:aws:iam::aws:policy/ReadOnlyAccess
```

## 주의

- 모든 User 에 `permissions_boundary_arn` 이 붙는다. 경계 정책이 허용하지 않는
  권한은 그룹 정책으로 줘도 실효되지 않는다.
- `iam_path` 를 바꾸면 User·Group·정책이 **재생성**된다 (IAM 은 경로 변경을
  in-place 로 지원하지 않는다). 시작할 때 정하고 그대로 둔다.
- 콘솔에서 이미 만든 사용자는 `import` 블록으로 편입한다
  ([docs/add-user.md](docs/add-user.md#기존-사용자-가져오기)).
