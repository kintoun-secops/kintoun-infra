# Bootstrap

`bootstrap/`은 Terraform 실행에 필요한 state 저장소와 CI 신뢰 기반을 만든다.
CI apply 역할의 자기 수정 방지 정책 때문에 운영자 자격증명으로 적용한다.

| 관리하는 것 | 다른 곳에서 준비하는 것 |
| --- | --- |
| S3 state 버킷과 버전 관리·암호화·공개 접근 차단 | 기존 `KintounGuardrailBoundary` 등 권한 경계 정책 |
| GitHub OIDC 공급자와 plan/apply 역할 | GitHub 조직·저장소 설정과 main 보호 규칙 |
| state 접근, plan 읽기 제한, apply 자기 수정 방지 | Wazuh와 사람 IAM 계정 |

## 입력과 출력

설정 템플릿은
[`bootstrap/example.tfvars`](https://github.com/kintoun-secops/kintoun-infra/blob/main/bootstrap/example.tfvars)다.

| 입력 | 의미 |
| --- | --- |
| `github_org`, `github_repo` | OIDC 신뢰를 허용할 저장소 좌표 |
| `github_sub_prefix` | immutable subject를 사용하는 조직의 실제 OIDC 접두사. 생략하면 이름 기반 좌표 |
| `state_bucket_name` | 기본 `kintoun-tfstate`. 모든 루트의 `backend.tf`와 일치해야 함 |
| `permissions_boundary_arn` | CI 역할에 적용할 기존 권한 경계 |
| `plan_role_policy_arns` | 기본 `ReadOnlyAccess` |
| `apply_role_policy_arns` | 기본 `PowerUserAccess`, `IAMFullAccess`. 최소 권한으로 축소할 대상 |

| 출력 | 용도 |
| --- | --- |
| `plan_role_arn` | GitHub Actions Variable `AWS_PLAN_ROLE_ARN` |
| `apply_role_arn` | GitHub Actions Variable `AWS_APPLY_ROLE_ARN` |
| `oidc_provider_arn` | OIDC 공급자 확인 |
| `state_bucket` | 다른 루트의 backend 설정 확인 |

## 기존 프로젝트에서 실행

Terraform 1.11 이상과 운영자 AWS 자격증명이 필요하다. 저장소 루트에서 실행한다.

```bash
export AWS_PROFILE=kintoun-admin
terraform -chdir=bootstrap init -input=false
terraform -chdir=bootstrap plan -var-file=example.tfvars
terraform -chdir=bootstrap apply -var-file=example.tfvars
```

현재 저장소는 `bootstrap/backend.tf`가 이미 활성화되어 있다.
기존 환경에서는 이 파일을 이동하거나 새 버킷을 만드는 절차를 반복하지 않는다.

## 새 AWS 환경을 처음 구성할 때

이 절차는 state 버킷도 기존 state도 없는 신규 환경용이다. 버킷 이름, 저장소 좌표,
경계 ARN을 먼저 수정한다. backend는 변수를 참조할 수 없으므로 모든
`backend.tf`의 `bucket`도 함께 수정한다.

```bash
export AWS_PROFILE=kintoun-admin
cd bootstrap

# 아직 없는 버킷으로 init하지 않도록 backend 설정을 임시 비활성화한다.
mv backend.tf backend.tf.disabled
terraform init
terraform plan -var-file=example.tfvars
terraform apply -var-file=example.tfvars

# 버킷 생성 성공 후 로컬 state를 S3로 이관한다.
mv backend.tf.disabled backend.tf
terraform init -migrate-state
terraform state list
```

실패한 경우 로컬 state와 비활성화한 backend 파일을 보존하고 실패 원인을 해결한다.
이관 완료와 원격 state를 확인한 뒤 로컬 state 잔여물을 정리한다.

## GitHub 연결

1. 저장소 Settings → Secrets and variables → Actions → Variables에
   `AWS_PLAN_ROLE_ARN`과 `AWS_APPLY_ROLE_ARN`을 등록한다.
2. OIDC subject와 trust 조건이 실제 저장소 설정에 맞는지 확인한다.
3. main 보호 규칙의 필수 검사를 `terraform plan / result`로 설정한다.
   문서 빌드도 필수로 요구하려면 `docs / build`를 추가한다.
4. PR의 전체 루트 plan 결과를 확인한다. main 머지 시 apply가 동작한다.

Access Analyzer의 GitHub 페더레이션 finding도 확인한다. 의도한 접근으로 검토한
finding은 팀의 감사 기준에 맞춰 아카이브 규칙을 등록하고, apply 역할의 넓은
관리형 정책은 최소 권한으로 축소할 작업 목록에 남긴다.

apply 역할의 보호 정책을 수정할 때도 이 루트를 운영자가 직접 적용한다.
새 루트의 state key가 `<디렉터리>/terraform.tfstate` 규칙을 따르면 state 권한을
추가하거나 bootstrap을 다시 적용할 필요는 없다.

## State 보존

버킷은 `prevent_destroy`, SSE-S3(AES256), 버전 관리와 공개 접근 차단을 사용한다.
현재 수명 주기 규칙은 과거 버전을 30일 뒤 만료시키고 삭제 마커를 정리한다.
미완료 멀티파트 업로드는 7일 뒤 정리한다. 복구 절차는
[State와 장애 대응](../runbooks/terraform.md)에 있다.
