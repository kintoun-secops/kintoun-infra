# 루트 모듈 규칙

전체 흐름은 [아키텍처](architecture.md)와 [CI 개요](ci/index.md)를 참고한다.

루트 모듈(디렉터리) 하나가 state 하나, apply 단위 하나다. CI 는 디렉터리 이름을 모른다 —
`backend.tf` 와 `terraform-roots.json` 만 보고 루트를 찾는다.

## 디렉터리와 state key

- 이름은 소문자·숫자·하이픈, 깊이는 2 까지 (`identity`, `platform/network`, `lab/victim`).
- `backend.tf` 의 `key` 는 반드시 `<디렉터리>/terraform.tfstate` 다. CI 롤의 S3 권한이 이 패턴이다.
- `terraform-roots.json` 에 같은 경로로 항목을 두고, 먼저 apply 되어야 하는 루트를 `depends_on` 에 적는다.
  매니페스트 형식과 검증 규칙은 [저장소 구조](structure.md#루트-매니페스트-작성)에 있다.
- 스캔 결과와 매니페스트가 다르면 `lint`·`discover` 잡이 실패한다. 조용히 빠지는 루트는 없다.
- `bootstrap/` 은 사람이 apply 하므로 매니페스트에 없다.
- 새 루트는 이웃 루트의 `.terraform.lock.hcl` 을 복사해서 시작한다.
- 새 루트의 범위·입력·출력은 저장소의 `docs/modules/<루트>.md` 에 작성하고
  `mkdocs.yml` 의 `nav` 에 등록한다. 중첩 루트도 같은 경로를 따른다
  (`platform/network` → `docs/modules/platform/network.md`).

## 파일

| 파일 | 내용 |
| --- | --- |
| `backend.tf` | backend 블록만 |
| `versions.tf` | `terraform {}` 블록만 (required_version, required_providers) |
| `providers.tf` | `provider` 블록만 |
| `main.tf` | 리소스·데이터 소스. 한 그룹이 150줄을 넘을 때만 `iam.tf` 처럼 이름 있는 파일로 뺀다 |
| `remote_state.tf` | 다른 루트의 출력을 읽는 `terraform_remote_state` 와 그 값을 담는 locals |
| `variables.tf`, `outputs.tf` | 알파벳 순, 한 줄 description |
| `files/` | Terraform 이 `file()` 로 읽는 정적 파일 (user_data 스크립트 등) |
| `templates/*.tftpl` | `templatefile()` 로 렌더링하는 파일 |

기술 문서는 저장소 최상위 `docs/` 에 모은다. 모듈 문서는 `docs/modules/`,
운영 절차는 `docs/runbooks/`, 그림은 `docs/assets/` 에 둔다.
최상위 `README.md` 는 프로젝트 소개와 문서 실행 안내를 제공한다.

`terraform-roots.json`은 들여쓰기 2칸, LF 줄바꿈, 줄 끝 공백 없음, 파일 끝 개행 1개로 저장한다.
`terraform fmt`의 검사 대상이 아니므로 PR lint에서 별도로 검사한다.
수정 후 저장소 루트에서 `node .github/scripts/fmt-roots.js --write`로 정리한다.

## 루트 사이의 참조

- 다른 루트가 쓸 값은 `outputs.tf` 에 내놓는다. 자식 모듈의 출력은 밖에서 보이지 않는다.
- 소비자는 `terraform_remote_state` 로 읽는다. 생산자 루트를 `depends_on` 에 적는다.
- 리소스 이름을 하드코딩하거나 태그로 조회해서 우회하지 않는다.

## CI 가 하는 일

- PR: 모든 루트를 `fmt`·`validate`·`tflint`·`plan` 하고 루트별 plan 코멘트, IAM 가드 코멘트, apply 순서(wave) 코멘트를 단다.
  브랜치 보호의 required check 는 `terraform plan / result` 하나다.
- main 머지: 매니페스트의 `depends_on` 깊이대로 계산한 모든 wave를 순서대로 `plan -detailed-exitcode` 후 변경이 있을 때만 apply한다.
  같은 wave의 루트는 한 실행 안에서 차례로 처리한다. 연속 실행은 최대 100개까지 대기 시작 시각 순으로 처리한다.
  대기 시작 시각은 커밋 순서와 다를 수 있다.
- 재실행은 Actions 의 `terraform apply` → Run workflow (main) 로 한다.

## 잠금이 남았을 때

취소된 plan 이 `.tflock` 을 남기면 다음 실행이 60초 기다리다 실패한다.
잠금 주인이 없는 것을 확인한 뒤 사람이 푼다:

```bash
AWS_PROFILE=kintoun-admin terraform -chdir=<루트> force-unlock <lock-id>
```

실패 유형별 확인과 state 복구는 [State와 장애 대응](runbooks/terraform.md)에 있다.

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

**흐름** — 브랜치 → PR (CI 가 모든 루트 모듈을 fmt·validate·tflint·plan 하고
루트 모듈별로 PR 코멘트 게시) → 리뷰 승인 → squash merge → main push 로 `depends_on` 순서대로 apply.
