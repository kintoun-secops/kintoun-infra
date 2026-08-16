# kintoun-infra

근두운 IaC 저장소 골격. 루트 모듈(디렉터리) 하나가 state 하나, apply 단위 하나다.

```
bootstrap/   원격 state 버킷 + GitHub OIDC + CI 롤. 로컬에서 1회 apply (WBS 2130·2140)
platform/    본 인프라 — VPC(2210), IAM(2220). 파이프라인이 apply
modules/     재사용 모듈 (같은 코드를 두 번째 쓸 때 생성)
.github/     PR 템플릿(2110) + plan/apply 워크플로우(2140)
```

## 사전 확인 (apply 전)

1. 이 저장소가 **GitHub 조직 소유**인지 — OIDC sub 조건이 `repo:<조직>/<저장소>` 좌표에 묶인다.
2. `bootstrap/example.tfvars` 의 `github_org` 를 채운다.
3. **권한 경계**: 팀 IAM 설계에 "신규 IAM 개체에 경계 강제"가 걸려 있으면
   `permissions_boundary_arn` 없이는 롤 생성이 거부된다. 콘솔에서 경계 정책
   ARN 을 확인해 기입한다. (강제가 없더라도 붙이는 것이 팀 설계와 일치)
4. 버킷 이름은 전역 유일이다. 바꾸면 세 곳을 함께 수정:
   `bootstrap/variables.tf` 기본값, `bootstrap/backend.tf.example`, `platform/backend.tf`.

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

## platform 사용

bootstrap 완료 후에만 `terraform init` 이 동작한다 (backend 버킷 필요).
기존 콘솔 생성 IAM 을 편입할 때는 import 블록과
`terraform plan -generate-config-out=generated.tf` 를 쓴다.
