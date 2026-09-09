# CI 스크립트

`.github/scripts/`에는 루트 탐색, plan 대상 선별, 정책 검사, 코멘트 본문 생성과 테스트가 있다.
워크플로가 실행 순서와 자격증명을 맡고, 스크립트는 입력을 검사하거나 결과를 조합한다.
전체 job 흐름은 [PR plan과 코멘트](plan.md), 루트 등록 규칙은 [저장소 구조](../structure.md)에 있다.

## 실행 스크립트

| 파일 | 호출 위치 | 입력과 결과 | 외부 접근 |
| --- | --- | --- | --- |
| [`tf-roots.js`](https://github.com/kintoun-secops/kintoun-infra/blob/main/.github/scripts/tf-roots.js) | PR의 `lint`, `discover`와 main의 `discover` | `backend.tf`와 `terraform-roots.json`을 대조하고 루트 목록과 apply wave를 계산 | 없음 |
| [`tf-targets.js`](https://github.com/kintoun-secops/kintoun-infra/blob/main/.github/scripts/tf-targets.js) | PR의 `discover` | 변경 파일 목록과 `tf-roots.js`의 결과로 plan 대상 루트와 생략 루트를 계산 | 없음. 변경 파일 조회는 앞의 스텝이 담당 |
| [`wave-comment.js`](https://github.com/kintoun-secops/kintoun-infra/blob/main/.github/scripts/wave-comment.js) | PR의 `wave-comment` | `tf-roots.js`의 계산 결과로 Mermaid와 순서 표를 포함한 Markdown 생성 | 없음. 게시는 뒤의 댓글 액션이 담당 |
| [`validate-iam-policies.js`](https://github.com/kintoun-secops/kintoun-infra/blob/main/.github/scripts/validate-iam-policies.js) | 각 루트의 `plan` | plan JSON에서 IAM 정책을 추출하고 Access Analyzer 결과를 실행 요약에 표시 | AWS. CI의 plan 역할 사용 |
| [`plan-summary.js`](https://github.com/kintoun-secops/kintoun-infra/blob/main/.github/scripts/plan-summary.js) | 모든 plan이 끝난 뒤 `plan-summary` | 루트별 아티팩트로 IAM 가드 본문과 변경 없는 platform plan 요약 생성 | GitHub. 위험 라벨 추가와 제거에 사용 |

### 루트 매니페스트 포맷

저장소 루트에서 실행한다. `terraform-roots.json`만 검사하며 루트 목록과 의존 관계의 값은 바꾸지 않는다.

```bash
node .github/scripts/fmt-roots.js --check
node .github/scripts/fmt-roots.js --write
```

`--check`는 들여쓰기 2칸, LF 줄바꿈, 줄 끝 공백 없음, 파일 끝 개행 1개인지 검사한다.
형식이 다르면 종료 코드 1과 정리 명령을 출력한다. `--write`는 키와 배열 순서를 유지하며 정리한다.
JSON 구문 오류는 두 모드 모두 실패하며 원본을 덮어쓰지 않는다.

### 루트 탐색과 wave 계산

저장소 루트에서 실행한다. Node.js만 필요하며 AWS 자격증명은 사용하지 않는다.

```bash
node .github/scripts/tf-roots.js
node .github/scripts/tf-roots.js --list
node .github/scripts/tf-roots.js --slug platform/network
```

기본 출력은 `roots`와 `waves`를 가진 JSON이다. `--list`는 루트 경로를 한 줄씩,
`--slug`는 아티팩트에 사용할 이름을 출력한다. `platform/network`의 슬러그는 `platform__network`다.
CI의 `--github-output` 모드는 `$GITHUB_OUTPUT`에 `roots`와 각 `waveN` 배열을 기록한다.
검증 오류는 `::error::`로 출력하고 종료 코드 1로 끝낸다.

### plan 대상 선별

Node.js와 [terraform-config-inspect](https://github.com/hashicorp/terraform-config-inspect)가 필요하다.
HCL과 Terraform JSON 해석은 이 도구가 맡으며 `terraform init`이나 AWS 접근은 필요하지 않다.
CI 설치 버전은 `.github/actions/setup-tf-config-inspect/action.yml`에 고정한다.
로컬에서는 Go가 설치된 환경에서 다음 명령으로 같은 버전을 준비하고 Go의 bin 경로를 PATH에 추가한다.

```bash
go install github.com/hashicorp/terraform-config-inspect@75d64de68c31445dbe4ee8308350e0b6dda1571d
export PATH="$(go env GOPATH)/bin:$PATH"
```

```bash
git diff --name-only --no-renames main...HEAD | node .github/scripts/tf-targets.js
node .github/scripts/tf-targets.js --changed changed-files.txt
node .github/scripts/tf-targets.js --all
```

변경 파일 경로를 한 줄씩 표준 입력이나 `--changed` 파일로 받는다. 이름이 바뀐 파일은 이전 경로도 넣는다.
기본 출력은 루트별 실행 여부와 사유를 적은 표다. `--all`은 목록과 무관하게 전체 루트를 대상으로 한다.
CI의 `--github-output` 모드는 `$GITHUB_OUTPUT`에 `targets`와 `skipped` 배열을 기록하고
같은 표를 job 요약에 남긴다. 선별 규칙은 [PR plan과 코멘트](plan.md#plan-대상-선별)에 있다.
전체 대상 경로는 `FULL_PLAN_PATHS`, 루트와 참조 모듈 밖의 제외 경로는 `IGNORED_PATHS`에 있다.
워크플로나 스크립트 구성을 바꾸면 함께 고친다. 어느 규칙에도 없는 파일은 전체 루트를 대상으로 한다.
`tf-module-sources.js`가 `.tf`와 `.tf.json`의 모듈 경로를 읽고, `tf-targets.js`가 이를 따라가며 소비 루트를 고른다.
변수나 local을 쓰는 `source` 또는 구성 해석 오류는 전체 plan으로 처리한다. 분석 도구 실행 실패는 검사 실패다.
매니페스트 검증에 실패하면 `tf-roots.js`와 같이 `::error::`를 출력하고 종료 코드 1로 끝낸다.

### apply 순서 코멘트 미리 보기

```bash
node .github/scripts/wave-comment.js
node .github/scripts/wave-comment.js --out /tmp/kintoun-apply-order.md
```

기본값은 표준 출력이며 `--out`을 주면 Markdown 파일에 쓴다. 이 명령 자체는 댓글을 게시하지 않는다.
CI에서는 렌더링 다음 스텝의 sticky 댓글 액션이 게시한다.
매니페스트가 잘못됐거나 루트가 없으면 이전 댓글만 갱신하도록 `only_update=true`를 출력한다.
`tf-roots.js`가 검증 실패를 job 실패로 처리하고, 이 스크립트는 그 상황을 설명하는 본문을 만든다.

### IAM 정책 본문 검사

`validate-iam-policies.js`는 `<plan.json> <region>`을 인자로 받는다.
계획된 값의 루트와 자식 모듈을 순회하며 사용자, 그룹, 역할의 인라인 정책,
관리형 정책과 역할의 신뢰 정책을 검사한다.
정책 본문을 임시 파일로 만들어 `aws accessanalyzer validate-policy`에 전달하고 종료 시 정리한다.

검사할 정책이 아직 확정되지 않았거나 `ERROR`, `SECURITY_WARNING`이 있으면 종료 코드 1이다.
API 오류, 잘못된 JSON과 지원하지 않는 plan 형식도 실패한다.
워크플로에서는 이 단계를 자문형으로 실행하므로 결과를 실행 요약에서 확인한다.
실제 병합 차단 기준은 별도의 `terraform.guardrail` Rego 검사다.

!!! warning "plan JSON은 러너 안에서만 처리합니다"
    `plan.json`에는 민감값이 포함될 수 있습니다. Git, PR 댓글, 아티팩트에 올리지 않습니다.
    정책 검사는 CI의 plan 역할로 실행하며, 로컬 AWS 조회가 필요할 때는 `kintoun-admin`을 명시합니다.

### matrix 결과를 용도별 코멘트로 모으기

각 plan job은 `iam-findings-<슬러그>` 아티팩트를 올린다.
`plan-summary` job은 matrix 밖에서 한 번 실행되며, 아티팩트를 내려받은 뒤
`plan-summary.js`를 모듈로 호출한다. 단독 CLI가 아니므로 `node plan-summary.js`로 게시하지 않는다.

| 입력 파일 | 의미 |
| --- | --- |
| `iam-findings.json` | conftest가 만든 IAM 판정 메시지 |
| `plan-failed` | plan 또는 JSON 추출 실패 표식 |
| `plan-status.json` | plan 종료 코드로 판정한 `no_changes` boolean. 리소스 값은 포함하지 않음 |

호출할 때 GitHub API 클라이언트, PR 문맥, Actions 출력 도구와 함께
`findingsDir`, `outFile`, `expectedDirs`, `skippedDirs`를 전달한다.
`expectedDirs`는 discover가 고른 plan 대상 루트이며, 파일이 누락된 루트를 검사 완료로 간주하지 않는다.
`skippedDirs`는 변경 영향이 없어 생략한 루트이며 실패로 세지 않는다.
대상 루트가 있으면 본문에 생략 목록을 적고, 대상이 하나도 없으면 목록 대신 모두 생략했다는 문장을 적는다.
기대 목록이 비어도 생략 목록이 있으면 검사 완료로 보고 기존 코멘트만 갱신한다.
두 목록이 모두 비어 있으면 discover 실패로 보고 미검사로 표시한다.

스크립트는 IAM 본문을 `outFile`에 쓰고 `only_update`를 출력한다.
추가로 `unchanged_body`와 `unchanged_delete`를 출력하여 변경 없는 platform plan을 묶거나
더 이상 해당하는 루트가 없을 때 요약 댓글을 삭제한다. 실제 게시와 삭제는 뒤의 sticky 댓글 액션이 수행한다.
액션의 boolean 입력은 빈 문자열 대신 항상 `true` 또는 `false`를 사용한다.

!!! note "변경 없음은 Terraform 종료 코드로 구분합니다"
    추가, 변경, 삭제가 모두 0이어도 import나 state 관리 해제가 있으면 상세 plan을 유지합니다.
    요약에는 종료 코드가 0인 `platform`과 그 하위 루트만 들어갑니다.

## 테스트 스크립트

| 파일 | 확인하는 것 |
| --- | --- |
| `test-fmt-roots.js` | JSON 포맷 오류와 구문 오류, 검사 시 원본 보존, 자동 정리와 재실행 |
| `test-tf-roots.js` | 임시 디렉터리에서 루트 발견, 제외 경로, state key, 의존성 오류와 동적 wave 계산 |
| `test-tf-targets.js` | 변경 파일별 대상 루트, `depends_on` 소비 루트, HCL·JSON 로컬 모듈과 간접 참조, 미확정 source, 전체 대상 경로와 생략 규칙 |
| `test-validate-iam-policies.js` | 예제 JSON의 정책 추출, 자식 모듈, 미확정 정책, 형식 버전과 표 렌더링 |
| `test-plan-summary.js` | 누락·잘못된 판정 결과의 미검사 표시와 라벨 유지, 생략 루트의 표시와 대상 없음 처리, boolean 출력과 변경 없는 platform plan 집계 |

모두 AWS 접근 없이 실행한다. plan 요약 테스트의 GitHub API도 모의 객체로 대체한다.
JavaScript 테스트는 Node.js, plan 대상 선별 테스트는 추가로 terraform-config-inspect, Rego 정책 테스트는 conftest가 필요하다.
CI의 conftest 버전은 워크플로의 `CONFTEST_VERSION`으로 고정한다.

```bash
node .github/scripts/test-fmt-roots.js
node .github/scripts/test-tf-roots.js
node .github/scripts/test-tf-targets.js
node .github/scripts/test-validate-iam-policies.js
node .github/scripts/test-plan-summary.js
```

이 명령들은 PR의 `lint`에서도 실행한다. 별도 npm 설치는 필요하지 않으며 terraform-config-inspect는 앞서 안내한 버전을 설치한다.
정책 규칙 자체의 테스트는 `conftest verify --policy .github/policy`로 실행한다.
규칙의 범위와 작성 방법은 [Rego 정책](rego.md)에 있다.
스크립트의 입출력이나 호출 방식을 바꾸면 해당 워크플로와 이 안내를 함께 갱신한다.
