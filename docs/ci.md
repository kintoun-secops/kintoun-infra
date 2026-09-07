# Terraform CI

CI는 `backend.tf`를 표식으로 루트를 탐색하고
`terraform-roots.json`과 대조한다. 디렉터리 목록을 워크플로에 직접 쓰지 않는다.
루트별 PR 검사는 재사용 워크플로 `_tf-root.yml`에서 실행하고,
main 적용은 `terraform-apply.yml`의 반복문에서 실행한다.
`.github/scripts/`의 파일별 역할과 실행 방법은 [CI 스크립트](ci-scripts.md)를 참고한다.

## PR 검사

`terraform-plan.yml`은 모든 PR에서 실행하며 경로 필터를 두지 않는다.
문서만 변경한 PR도 모든 Terraform 루트를 검사한다.

| Job | 수행 내용 |
| --- | --- |
| `lint` | fmt, 루트 탐색 테스트·검증, backend 없는 init/validate, TFLint, Rego·IAM 스크립트 테스트 |
| `discover` | 루트 목록을 검증하고 plan matrix 출력 |
| `wave-comment` | 매니페스트의 `depends_on`으로 apply 순서(wave)를 Mermaid 그래프와 표로 그려 코멘트 하나로 게시 |
| `plan` | 모든 루트를 병렬 plan, 정책 검사, 루트별 plan 코멘트 |
| `iam-comment` | 루트별 아티팩트를 수집해 IAM 가드와 변경 없는 platform plan을 각각 하나의 코멘트로 통합 |
| `result` | 항상 실행하여 lint·discover·plan 성공 여부 집계 |

`matrix`는 같은 job을 목록의 각 값으로 나눠 실행하는 기능이다.
`discover`가 찾은 루트 목록을 `matrix.dir`에 넣으므로 루트가 4개면 plan job도 4개가 된다.
각 plan은 결과 아티팩트를 올리고, matrix 밖의 `iam-comment`는 `needs: [discover, plan]`으로
모든 plan이 끝나기를 기다린 뒤 한 번만 실행하여 결과를 모아 코멘트를 작성한다.
main의 apply는 matrix를 쓰지 않고 job 하나가 의존 순서대로 루트를 반복 실행한다.

`bootstrap`은 lint의 validate 대상이지만 자동 plan/apply matrix에는 들어가지 않는다.
같은 PR의 새 커밋은 이전 plan을 취소한다. 서로 다른 PR의 state 잠금 경합은
S3 잠금과 60초의 `-lock-timeout`으로 처리한다.

!!! info "변경 없는 platform plan은 한곳에 표시합니다"
    `platform`과 하위 루트의 plan이 `No changes`이면 요약 코멘트 하나에 모아 표시합니다.
    이전 커밋의 해당 루트 상세 코멘트는 정리합니다. 다시 변경이 생기면 상세 코멘트로 표시합니다.
    import, state 관리 해제와 출력 변경은 Terraform 종료 코드가 2이므로 상세 plan을 유지합니다.
    실패하거나 검사 결과가 누락된 루트는 변경 없음으로 표시하지 않습니다.

브랜치 보호에서 고정할 필수 검사는 **`terraform plan / result`**다.
기존 `plan (platform)`, `plan (identity)` 같은 루트별 항목을 사용 중이면 교체한다.
현재 result는 `wave-comment`와 `iam-comment` 완료를 기다리지만 두 job의 성공 여부를 별도 조건으로 검사하지 않는다.

## 정책 검사의 의미

| 검사 | 실패 시 동작 |
| --- | --- |
| AWS Access Analyzer | 자문형. 정책 본문 검사 결과를 job summary에 표시 |
| `terraform.iam` | 자문형. 사용자 삭제·교체, 권한 경계 변경, 특권 정책 등 검토 사항을 코멘트에 표시 |
| `terraform.guardrail` | 차단형. 경계 없는 인프라 역할이나 `/project/` 밖의 역할 생성을 plan 실패로 처리 |

`terraform.iam`의 Rego `deny`는 검토 분류이며 그 자체로 PR을 차단하지 않는다.
`terraform.guardrail`의 결과가 실제 차단 조건이다. 코멘트의 `[차단]` 표시와
job 결과를 함께 확인한다.

`tfplan`과 `plan.json`은 러너 내부에서만 처리하고 정리한다.
공유하는 것은 판정 메시지, 실패 표식과 변경 여부만 담은 `plan-status.json`이며 IAM 아티팩트는 1일 보관한다.
중첩 루트 `platform/network`의 아티팩트 이름은 `platform__network`로 변환한다.

### 정책 규칙 작성

규칙은 `.github/policy/`의 Rego 파일에서 관리한다.

- AWS 리소스 타입(`aws_iam_*`)과 plan 액션을 기준으로 판정한다. 저장소의 변수명이나
  파일 구조를 파싱하지 않아 모듈을 리팩터링해도 같은 규칙을 적용한다.
- 필수 필드가 없거나 `null`이면 준수를 확인할 수 없는 값으로 처리한다.
  Rego의 `null`은 정의된 값이므로 `not 필드`만으로 검사하지 않는다.
  없는 키에 바인딩한 규칙이 실행되지 않는 경우도 고려해
  `iam.boundary`, `guardrail.compliant_path`처럼 준수 조건을 명시한다.
- 규칙 메시지는 PR 코멘트에 그대로 표시되므로 민감값을 포함하지 않는다.
- `*_test.rego`에 단위 테스트를 작성하고 `conftest verify --policy .github/policy`로 확인한다.
  CI의 `lint`도 같은 검증을 수행한다.

## apply 순서 코멘트

`wave-comment`는 자격증명 없이 `tf-roots.js`와 같은 계산을 다시 수행하므로 plan을 기다리지 않는다.
루트가 하나 이상 있으면 wave별 `subgraph`와 `depends_on` 화살표로 그린 Mermaid 그래프,
wave 번호와 `depends_on`을 적은 표를 `apply-order` 헤더의 sticky 코멘트로 게시한다.
GitHub가 코멘트의 Mermaid 블록을 직접 그리므로 이미지 파일을 만들거나 올리지 않는다.

매니페스트 검증에 실패하거나 루트가 없는 커밋은 새 코멘트를 만들지 않고, 이전 커밋의 코멘트가
있을 때만 계산 실패 사유로 갱신한다(`only_update`). 성공 본문에는 커밋 정보를 넣지 않으므로
매니페스트가 같으면 코멘트를 다시 쓰지 않는다(`skip_unchanged`).
로컬에서는 `node .github/scripts/wave-comment.js`로 그래프와 표를 미리 볼 수 있다.
실패 본문의 커밋 SHA와 로그 링크는 CI에서만 붙는다.

## Main 적용

`terraform-apply.yml`은 main push와 수동 실행을 지원한다.
`tf-roots.js`가 `depends_on` 그래프의 깊이를 계산하고, apply job이 결과 배열을 반복하며
모든 wave를 순서대로 실행한다. 같은 wave의 루트는 한 job 안에서 차례로 적용한다.

각 루트는 같은 러너에서 `plan -detailed-exitcode -out=tfplan`을 실행한다.

| 종료 코드 | 처리 |
| --- | --- |
| `0` | 변경 없음, apply 생략 |
| `2` | 생성한 `tfplan`을 apply |
| 그 외 | 실패 |

워크플로의 `queue: max`가 최대 100개 실행을 대기시킨다. 한 실행 안에서는 루트별
plan과 apply가 연속으로 실행된다. 대기열은 대기 시작 시각의 FIFO이며 커밋 순서를
보장하지는 않는다([GitHub concurrency 안내](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)).
문서처럼 `paths-ignore`에 해당하는 파일만 머지하면 자동 apply는 실행하지 않는다.
그 외 파일이 함께 바뀌거나 수동 실행하면 모든 루트를 다시 plan하므로
기존 인프라 드리프트가 있다면 apply 대상에 포함될 수 있다.
어느 루트에서든 init, plan 또는 apply가 실패하면 뒤의 루트와 wave는 실행하지 않는다.
plan 파일은 실패나 취소 시에도 정리한다.

수동 재실행은 Actions → terraform apply → Run workflow에서 **main**을 선택한다.
apply 역할의 OIDC trust가 main subject만 허용한다.

## 루트 추가와 의존성

탐색 결과와 매니페스트 불일치, 잘못된 state key, 미등록 의존성,
순환 의존성은 CI를 실패시킨다. wave 개수는 의존 깊이에 맞춰 계산하며 고정 상한을 두지 않는다.
등록 절차와 매니페스트 형식은 [저장소 구조](structure.md#루트-모듈-추가-절차)에 있다.

## 로컬 검증

```bash
terraform fmt -check -recursive
node .github/scripts/test-tf-roots.js
node .github/scripts/tf-roots.js
node .github/scripts/test-validate-iam-policies.js
node .github/scripts/test-iam-comment.js
conftest verify --policy .github/policy
bash .github/scripts/test-iam-pipeline.sh
```

backend 없이 구성 문법을 확인하려면 각 루트에서 `terraform init -backend=false`와
`terraform validate`를 실행한다. 실제 AWS plan과는 검증 범위가 다르다.
액션은 커밋 SHA로 고정하고 Dependabot이 갱신한다.

actionlint 1.7.12는 GitHub가 지원하는 `concurrency.queue`를 아직 인식하지 못한다.
해당 버전으로 로컬 검사할 때는 공식 문법을 확인한 뒤 그 진단만 제외한다.
문서 워크플로 자체는 예외 없이 검사할 수 있다.

```bash
actionlint .github/workflows/docs.yml
actionlint -ignore 'unexpected key "queue" for "concurrency" section'
```
