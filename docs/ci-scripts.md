# CI 스크립트

`.github/scripts/`에는 루트 탐색, 정책 검사, 코멘트 본문 생성과 테스트가 있다.
워크플로가 실행 순서와 자격증명을 맡고, 스크립트는 입력을 검사하거나 결과를 조합한다.
전체 job 흐름은 [Terraform CI](ci.md), 루트 등록 규칙은 [저장소 구조](structure.md)에 있다.

## 실행 스크립트

| 파일 | 호출 위치 | 입력과 결과 | 외부 접근 |
| --- | --- | --- | --- |
| [`tf-roots.js`](https://github.com/kintoun-secops/kintoun-infra/blob/main/.github/scripts/tf-roots.js) | PR의 `lint`, `discover`와 main의 `discover` | `backend.tf`와 `terraform-roots.json`을 대조하고 루트 목록과 apply wave를 계산 | 없음 |
| [`wave-comment.js`](https://github.com/kintoun-secops/kintoun-infra/blob/main/.github/scripts/wave-comment.js) | PR의 `wave-comment` | `tf-roots.js`의 계산 결과로 Mermaid와 순서 표를 포함한 Markdown 생성 | 없음. 게시는 뒤의 댓글 액션이 담당 |
| [`validate-iam-policies.js`](https://github.com/kintoun-secops/kintoun-infra/blob/main/.github/scripts/validate-iam-policies.js) | 각 루트의 `plan` | plan JSON에서 IAM 정책을 추출하고 Access Analyzer 결과를 실행 요약에 표시 | AWS. CI의 plan 역할 사용 |
| [`iam-comment.js`](https://github.com/kintoun-secops/kintoun-infra/blob/main/.github/scripts/iam-comment.js) | 모든 plan이 끝난 뒤 `iam-comment` | 루트별 아티팩트로 IAM 가드 본문과 변경 없는 platform plan 요약 생성 | GitHub. 위험 라벨 추가와 제거에 사용 |

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

### matrix 결과를 하나의 코멘트로 모으기

각 plan job은 `iam-findings-<슬러그>` 아티팩트를 올린다.
`iam-comment` job은 matrix 밖에서 한 번 실행되며, 아티팩트를 내려받은 뒤
`iam-comment.js`를 모듈로 호출한다. 단독 CLI가 아니므로 `node iam-comment.js`로 게시하지 않는다.

| 입력 파일 | 의미 |
| --- | --- |
| `iam-findings.json` | conftest가 만든 IAM 판정 메시지 |
| `plan-failed` | plan 또는 JSON 추출 실패 표식 |
| `plan-status.json` | plan 종료 코드로 판정한 `no_changes` boolean. 리소스 값은 포함하지 않음 |

호출할 때 GitHub API 클라이언트, PR 문맥, Actions 출력 도구와 함께
`findingsDir`, `outFile`, `expectedDirs`를 전달한다.
`expectedDirs`는 discover의 루트 목록이며, 파일이 누락된 루트를 검사 완료로 간주하지 않는다.

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
| `test-tf-roots.js` | 임시 디렉터리에서 루트 발견, 제외 경로, state key, 의존성 오류와 동적 wave 계산 |
| `test-validate-iam-policies.js` | 예제 JSON의 정책 추출, 자식 모듈, 미확정 정책, 형식 버전과 표 렌더링 |
| `test-iam-comment.js` | 누락된 판정 결과, 위험 라벨, boolean 출력과 변경 없는 platform plan 집계 |
| `test-iam-pipeline.sh` | 빈 plan 예제로 conftest 결과가 JSON 배열인지 확인하고 guardrail 검사까지 연결 |

모두 AWS 접근 없이 실행한다. IAM 코멘트 테스트의 GitHub API도 모의 객체로 대체한다.
JavaScript 테스트는 Node.js, 파이프라인 테스트는 Bash, jq, conftest가 필요하다.
CI의 conftest 버전은 워크플로의 `CONFTEST_VERSION`으로 고정한다.

```bash
node .github/scripts/test-tf-roots.js
node .github/scripts/test-validate-iam-policies.js
node .github/scripts/test-iam-comment.js
bash .github/scripts/test-iam-pipeline.sh
```

이 명령들은 PR의 `lint`에서도 실행한다. 별도 npm 설치는 필요하지 않다.
정책 규칙 자체의 테스트는 `conftest verify --policy .github/policy`로 실행한다.
스크립트의 입출력이나 호출 방식을 바꾸면 해당 워크플로와 이 안내를 함께 갱신한다.
