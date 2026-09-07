# 루트 모듈 규칙

루트 모듈(디렉터리) 하나가 state 하나, apply 단위 하나다. CI 는 디렉터리 이름을 모른다 —
`backend.tf` 와 `.github/terraform-roots.json` 만 보고 루트를 찾는다.

## 디렉터리와 state key

- 이름은 소문자·숫자·하이픈, 깊이는 2 까지 (`identity`, `platform/network`, `lab/victim`).
- `backend.tf` 의 `key` 는 반드시 `<디렉터리>/terraform.tfstate` 다. CI 롤의 S3 권한이 이 패턴이다.
- `.github/terraform-roots.json` 에 같은 경로로 항목을 두고, 먼저 apply 되어야 하는 루트를 `depends_on` 에 적는다.
- 스캔 결과와 매니페스트가 다르면 `lint`·`discover` 잡이 실패한다. 조용히 빠지는 루트는 없다.
- `bootstrap/` 은 사람이 apply 하므로 매니페스트에 없다.
- 새 루트는 이웃 루트의 `.terraform.lock.hcl` 을 복사해서 시작한다.

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
| `docs/` | 그림·런북 |
| `README.md` | "다루는 것 / 다루지 않는 것" 표 + 다른 루트에 내주는 출력 목록 |

## 루트 사이의 참조

- 다른 루트가 쓸 값은 `outputs.tf` 에 내놓는다. 자식 모듈의 출력은 밖에서 보이지 않는다.
- 소비자는 `terraform_remote_state` 로 읽는다. 생산자 루트를 `depends_on` 에 적는다.
- 리소스 이름을 하드코딩하거나 태그로 조회해서 우회하지 않는다.

## CI 가 하는 일

- PR: 모든 루트를 `fmt`·`validate`·`tflint`·`plan` 하고 루트별 plan 코멘트와 IAM 가드 코멘트를 단다.
  브랜치 보호의 required check 는 `terraform plan / result` 하나다.
- main 머지: 매니페스트의 `depends_on` 깊이대로 wave0 → wave3 순서로 `plan -detailed-exitcode` 후 변경이 있을 때만 apply.
  같은 wave 는 병렬이다. 연속 머지는 순서대로 모두 실행된다.
- 재실행은 Actions 의 `terraform apply` → Run workflow (main) 로 한다.

## 잠금이 남았을 때

취소된 plan 이 `.tflock` 을 남기면 다음 실행이 60초 기다리다 실패한다.
잠금 주인이 없는 것을 확인한 뒤 사람이 푼다:

```bash
AWS_PROFILE=kintoun-admin terraform -chdir=<루트> force-unlock <lock-id>
```
