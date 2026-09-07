# 저장소 구조

저장소는 루트 모듈 디렉터리, 재사용 모듈 자리, 기술 문서, CI 구성으로 나뉜다.
루트 모듈(디렉터리) 하나가 state 하나와 apply 단위 하나를 가진다.
CI는 디렉터리 이름을 워크플로에 적지 않고 `backend.tf`와
루트 매니페스트 `terraform-roots.json`만으로 루트를 찾는다.

## 디렉터리 구성

```text
bootstrap/                 S3 state 버킷, GitHub OIDC, plan/apply 역할. 운영자가 직접 apply
platform/                  기존 사용자 정책과 인프라 이전 기록
  network/                 공유 VPC, 서브넷과 라우팅
  wazuh/                   Wazuh EC2, 보안 그룹과 인프라 IAM
identity/                  팀원과 그룹 명단, 자격증명 정책
modules/                   재사용 모듈 자리. 루트 탐색 대상이 아니다
docs/                      MkDocs 기술 문서
  modules/                 루트별 범위, 입력, 출력
  runbooks/                운영 절차
  assets/                  그림
terraform-roots.json       CI가 plan/apply 하는 루트 목록과 apply 선후
.github/
  workflows/
    terraform-plan.yml     PR 검사. lint, discover, apply 순서 코멘트, 루트별 plan, IAM 코멘트, result
    terraform-apply.yml    main 적용. depends_on 깊이를 계산해 모든 wave를 반복 apply
    _tf-root.yml           루트 하나의 PR 검사를 실행하는 재사용 워크플로
    docs.yml               문서 strict 빌드와 HTML 아티팩트. 문서와 무관한 변경은 건너뜀
  scripts/                 루트 탐색, IAM 정책 검사, apply 순서와 IAM 코멘트 스크립트와 테스트
  policy/                  Rego 정책(guardrail, iam)과 테스트
  ISSUE_TEMPLATE/          이슈 템플릿
  pull_request_template.md PR 템플릿
  dependabot.yml           액션과 문서 의존성 갱신
mkdocs.yml                 문서 탐색 구조와 빌드 설정
requirements-docs.txt      문서 빌드 의존성
.tflint.hcl                TFLint 설정
```

## 루트 모듈 탐색 규칙

`.github/scripts/tf-roots.js`가 저장소를 순회해 `backend.tf`가 있는 디렉터리를
루트 모듈로 인식한다. 이름이 `.`으로 시작하는 디렉터리와 `.terraform`, `node_modules`,
`modules`는 순회하지 않는다. `bootstrap`은 운영자가 로컬에서 apply 하므로 탐색 결과에서
제외하며 lint의 validate 대상으로만 남는다.

탐색 결과는 루트 매니페스트와 정확히 일치해야 한다. 어느 한쪽에만 있는 루트가 있으면
PR의 `lint`·`discover` job과 main의 `discover` job이 실패한다.
등록되지 않은 루트가 조용히 빠지는 일은 없다.

## 루트 모듈 추가 절차

1. 디렉터리를 만든다. 이름은 소문자, 숫자, 하이픈만 쓰고 깊이는 2까지다.
   `lab/victim`처럼 중첩할 수 있고 `platform/network`처럼 기존 루트 아래에 둘 수도 있다.
2. `backend.tf`의 `key`를 `<디렉터리>/terraform.tfstate`로 둔다.
   CI 역할의 state 권한이 이 패턴이며 다른 값은 검증에서 실패한다.
3. 이웃 루트의 `.terraform.lock.hcl`, `versions.tf`, `providers.tf`를 복사한다.
   파일 구성은 [개발 규칙](conventions.md#파일)을 따른다.
4. 루트 매니페스트에 항목을 추가한다. 다른 루트의 출력을 `terraform_remote_state`로 읽는다면
   그 루트를 `depends_on`에 적는다. 형식은 [루트 매니페스트 작성](#루트-매니페스트-작성)에 있다.
5. `node .github/scripts/tf-roots.js`를 실행해 탐색 결과, 매니페스트, state key가 일치하는지 확인한다.
6. `docs/modules/<디렉터리>.md`에 범위, 입력, 출력을 작성하고 `mkdocs.yml`의 `nav`에 등록한다.
   중첩 루트는 `platform/network` → `docs/modules/platform/network.md`처럼 같은 경로를 따른다.

워크플로, 스크립트, bootstrap은 수정하지 않는다. 새 루트는 같은 PR부터 plan 대상이 되고
main에 머지되면 wave 순서에 따라 apply 된다.

## 루트 매니페스트 작성

`terraform-roots.json`은 CI가 plan/apply 하는 루트 목록과 apply 선후를 정한다.
`tf-roots.js`가 PR과 main의 모든 실행에서 이 파일을 검증하고 plan matrix와 apply wave를 만든다.

### 형식

```json
{
  "$comment": "CI 가 plan/apply 하는 루트 모듈과 apply 선후",
  "roots": {
    "identity": { "depends_on": [] },
    "platform/network": { "depends_on": [] },
    "lab/victim": { "depends_on": ["platform/network"] }
  }
}
```

위 JSON은 매니페스트 형식을 설명하는 예시다. `lab/victim`은 network의 VPC 출력을 읽는 후속 루트다.
실제 매니페스트는 wave0에 network와 identity, wave1에 wazuh, wave2에 기존 platform을 둔다.

| 필드 | 값 | 설명 |
| --- | --- | --- |
| `$comment` | 문자열 | 선택. 파일 설명이며 검증하지 않는다 |
| `roots` | 객체 | 필수. 키는 저장소 루트 기준 디렉터리 경로다 |
| `roots.<경로>` | 객체 | 필수. 허용하는 필드는 `depends_on` 하나다 |
| `roots.<경로>.depends_on` | 문자열 배열 | 필수. 먼저 apply 되어야 하는 루트 경로. 없으면 빈 배열 |

`roots` 안의 항목에 다른 필드를 넣으면 검증에서 실패한다. `roots` 밖의 최상위 키는 읽지 않는다.

### 검증 규칙

| 규칙 | 실패 메시지 |
| --- | --- |
| `backend.tf`가 있는 디렉터리는 모두 등록한다 | `<경로>: backend.tf 는 있는데 terraform-roots.json 에 없다` |
| 등록한 경로에 `backend.tf`가 있어야 한다 | `<경로>: terraform-roots.json 에는 있는데 backend.tf 가 없다` |
| 경로는 소문자, 숫자, 하이픈이고 깊이 2 이하다 | `<경로>: 이름 규칙 위반 (소문자·숫자·하이픈, 깊이 2 이하)` |
| 항목은 객체이고 `depends_on` 외 필드가 없다 | `<경로>: 허용되지 않는 필드 <필드>` |
| `depends_on`은 배열이다 | `<경로>: depends_on 은 배열이어야 한다` |
| 자기 자신에 의존하지 않는다 | `<경로>: 자기 자신에 의존한다` |
| 의존 대상은 매니페스트에 있어야 한다 | `<경로>: depends_on 의 <대상> 이 terraform-roots.json 에 없다` |
| `backend.tf`의 `key`는 `<경로>/terraform.tfstate`다 | `<경로>/backend.tf: key 가 "<값>" 인데 "<경로>/terraform.tfstate" 이어야 한다` |
| 순환 의존이 없다 | `순환 의존: a -> b -> a` |

### apply 순서 계산

`depends_on`이 없는 루트는 wave0, wave0에만 의존하는 루트는 wave1이 되는 식으로
의존 깊이에 따라 wave를 나눈다. 같은 wave는 한 apply job에서 차례로 실행하고 다음 wave는 앞 wave가
실패하지 않았을 때만 실행한다. 비어 있는 wave는 건너뛴다.
현재는 `platform/network`와 `identity`가 wave0에서 차례로 실행된다.
`platform/wazuh`는 wave1, 기존 `platform`은 wave2에서 적용된다. 이전 절차는
[Platform state 이전](runbooks/platform-migration.md)에 있다.

PR에서는 `wave-comment` job이 같은 계산 결과를 Mermaid 그래프와 표로 그려 코멘트로 남기므로
`depends_on`을 바꾼 PR은 코멘트에서 apply 순서 변화를 확인한다.
동작은 [Terraform CI](ci.md#apply-순서-코멘트)에 있다.

wave 개수에는 고정된 상한이 없다. `tf-roots.js`가 매니페스트의 최대 의존 깊이에 맞춰
배열을 만들고 `terraform-apply.yml`이 그 배열을 반복한다.

### 로컬 확인

```bash
node .github/scripts/tf-roots.js          # 루트 목록과 wave를 JSON으로 출력
node .github/scripts/tf-roots.js --list   # 루트 경로만 출력
node .github/scripts/test-tf-roots.js     # 탐색·검증 스크립트 자체 테스트
```

오류는 `::error::` 접두사를 붙여 stderr에 출력하고 종료 코드 1로 끝난다.
CI에서 discover가 실패하면 plan matrix가 비고 IAM 가드 코멘트는 미검사로 표시된다.
apply 순서 코멘트는 이전 커밋의 코멘트가 있을 때만 계산 실패로 갱신되고 없으면 게시하지 않는다.
매니페스트 오류로 plan이 실패했을 때의 확인 순서는 [State와 장애 대응](runbooks/terraform.md)에 있다.
