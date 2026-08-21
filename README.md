# kintoun-infra

근두운 IaC 저장소 골격. 루트 모듈(디렉터리) 하나가 state 하나, apply 단위 하나다.

```
bootstrap/   원격 state 버킷 + GitHub OIDC + CI 롤. 로컬에서 1회 apply (WBS 2130·2140)
platform/    본 인프라 — VPC(2210), 서비스 IAM(2220). 파이프라인이 apply
identity/    팀원 IAM — User·그룹 소속·자격증명 기본 정책(2220). 파이프라인이 apply
modules/     재사용 모듈 (같은 코드를 두 번째 쓸 때 생성)
.github/     이슈·PR 템플릿(2110) + plan/apply 워크플로우(2140)
```

## 사전 확인 (apply 전)

1. 이 저장소가 **GitHub 조직 소유**인지 — OIDC sub 조건이 `repo:<조직>/<저장소>` 좌표에 묶인다.
2. `bootstrap/example.tfvars` 의 `github_org` 를 채운다.
3. **권한 경계**: 팀 IAM 설계에 "신규 IAM 개체에 경계 강제"가 걸려 있으면
   `permissions_boundary_arn` 없이는 롤 생성이 거부된다. 콘솔에서 경계 정책
   ARN 을 확인해 기입한다. (강제가 없더라도 붙이는 것이 팀 설계와 일치)
4. 버킷 이름은 전역 유일이다. 바꾸면 세 곳을 함께 수정:
   `bootstrap/variables.tf` 기본값, `bootstrap/backend.tf`, `platform/backend.tf`,
   `identity/backend.tf`.

## 부트스트랩 절차 (로컬, 개인 자격증명 1회)

```bash
cd bootstrap
terraform init
terraform plan  -var-file=example.tfvars
terraform apply -var-file=example.tfvars

# 버킷이 생긴 뒤 bootstrap 자신의 state 도 버킷으로 이관
mv backend.tf.example backend.tf
terraform init -migrate-state
```

apply 출력의 `plan_role_arn` / `apply_role_arn` 을 저장소
Settings > Secrets and variables > Actions > **Variables** 에
`AWS_PLAN_ROLE_ARN` / `AWS_APPLY_ROLE_ARN` 으로 등록하면 파이프라인이 동작한다.

## 부트스트랩 직후 체크리스트

- [ ] main 보호 규칙 활성화 (2110 DoD) — apply 롤의 sub 가 main 전용이므로 한 쌍이다
- [ ] Access Analyzer 에 뜨는 GitHub 페더레이션 finding 을 **의도된 접근으로 아카이브 규칙** 등록
      (2220 DoD "외부 접근 0건" 검수용 예외)
- [ ] apply 롤을 "FullAccess -> 최소권한 리팩터링" 목록에 등재 (2차 보고서 이슈사항과 연동)
- [ ] 로컬에 `terraform.tfstate*` 파일이 남아 있지 않은지 확인 (이관 후 잔여물 삭제)

## platform / identity 사용

bootstrap 완료 후에만 `terraform init` 이 동작한다 (backend 버킷 필요).
기존 콘솔 생성 IAM 을 편입할 때는 import 블록과
`terraform plan -generate-config-out=generated.tf` 를 쓴다.

팀원 IAM 은 `identity/` 에서 관리한다. 추가·이탈 절차는 `identity/README.md`.

### 루트 모듈을 새로 팔 때

1. 디렉터리를 만들고 `backend.tf` 의 `key` 를 `<디렉터리>/terraform.tfstate` 로 둔다.
2. `bootstrap/oidc.tf` 의 `local.tfstate_keys` 에 같은 키를 추가하고
   **bootstrap 을 다시 apply** 한다. 안 하면 CI 롤이 state 를 못 읽어 init 이 깨진다.
3. `.github/workflows/terraform-plan.yml` / `terraform-apply.yml` 의
   `matrix.dir` 목록과 `on.paths` 에 디렉터리를 추가한다.

## Git 컨벤션

main 하나만 장수 브랜치로 둔다 (트렁크 기반). state 가 하나이므로 장기 브랜치는
드리프트를 만든다. 환경 분리는 브랜치가 아니라 루트 모듈 디렉터리로 한다.

**브랜치** — 소문자·하이픈, `<type>/<대상>-<내용>`

```
feat/wazuh-agent-sg      fix/wazuh-iam      chore/provider-bump
```

**커밋 / PR 제목** — `<type>(<scope>): <요약>`

```
type   feat | fix | refactor | chore | docs | ci | revert
scope  bootstrap | platform | platform/iam | identity | modules/<이름> | .github

feat(platform): OIDC trust policy 에 github_sub_prefix 변수 추가
fix(platform/iam): IAM 롤에 경로 접두사 적용
chore(platform): .terraform.lock.hcl 커밋
```

한 커밋에 변경 하나. 왜 바꿨는지는 본문에 적는다. WIP 커밋은 머지 전에 squash.

**흐름** — 브랜치 → PR (`platform/**`·`identity/**` 변경 시 CI 가 fmt·validate·plan 후
루트 모듈별로 PR 코멘트 게시) → 리뷰 승인 → squash merge → main push 로 apply.
