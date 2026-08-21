# policy — terraform plan JSON 검사

`conftest` 가 `terraform show -json` 출력을 읽어 판정한다. 패키지는 둘이다.

| 패키지 | 파일 | 성격 |
| --- | --- | --- |
| `terraform.iam` | `iam.rego` | 자문형. 결과는 PR 의 **IAM 가드** 코멘트로만 나가고 병합 여부는 리뷰어가 정한다. |
| `terraform.guardrail` | `guardrail.rego` | 차단형. `deny` 가 하나라도 있으면 plan 잡이 실패한다. 사유는 코멘트에도 남는다. |

guardrail 의 차단이 정당한 이유: 권한 경계 정책이 apply 시점에 어차피 거부할 위반(경계
없는 롤, `/project/` 밖의 롤)을 plan 시점으로 앞당길 뿐이다.

## 규칙 작성

- AWS 리소스 타입(`aws_iam_*`)과 plan 액션에만 건다. 저장소의 변수명이나 파일 구조를
  파싱하지 않으므로 모듈을 리팩터링해도 그대로 동작한다.
- 필드가 없거나 `null` 이면 위반으로 친다(fail-closed). Rego 에서 `null` 은 정의된 값이라
  `not 필드` 에 걸리지 않고, 없는 키를 바인딩하면 규칙 본문이 undefined 가 되어 발화하지
  않는다. "준수임이 증명될 때만 통과" 형태로 쓴다(`iam.boundary`, `guardrail.compliant_path`).

## 테스트

```bash
conftest verify -p .github/policy
```

`*_test.rego` 가 단위 테스트다. CI 의 `lint` 잡이 같은 명령을 돌린다.

## plan JSON 취급

plan JSON 은 민감값을 평문으로 담는다. `tfplan`·`plan.json` 은 러너 안에서만 쓰고
artifact 로 올리거나 코멘트에 붙이지 않는다. 올리는 것은 판정 결과 `conftest.json` 뿐이며,
규칙 메시지도 그대로 코멘트에 실리므로 민감값을 담지 않는다.
