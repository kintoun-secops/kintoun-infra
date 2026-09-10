# KMS 검사

KMS 변경은 `kms.rego`의 `terraform.kms`에서 검사하고 `kms-summary.js`가 PR 라벨과
`kms-guard` 코멘트로 보고한다. 기존 IAM 자문 검사와 같이 검토 신호를 제공하며 병합을 차단하지 않는다.
필수 검사로 차단하는 범위는 [인프라 역할 가드레일](rego.md#인프라-역할-가드레일)이다.

## 변경 감지와 라벨

Terraform plan JSON의 `aws_kms_*` 리소스 변경을 대상으로 한다.
키뿐 아니라 별칭, grant, 별도 `aws_kms_key_policy`도 포함하며 자식 모듈 안의 리소스도 같은 기준으로 검사한다.
일반 `no-op`과 `read`는 제외하고, import는 `no-op`이어도 포함한다.
AWS 리소스의 태그를 바꾸는 기능은 아니며 PR에 GitHub 라벨을 붙인다.

| 라벨 | 추가 조건 | 제거 조건 |
| --- | --- | --- |
| `kms` | KMS 리소스 변경이 하나 이상 확인됨 | 모든 plan 대상의 KMS 검사가 완료되고 변경이 없음 |
| `kms:high-risk` | 위험 판정이 하나 이상 있음 | 모든 plan 대상의 KMS 검사가 완료되고 위험 판정이 없음 |

`kms`는 규칙 위반이 없어도 붙는다. 키 정책, 자동 회전, 삭제 계획을 함께 검토할 PR이라는 표시다.
IAM 정책의 KMS 권한이나 S3·EBS의 암호화 설정만 바뀌고 `aws_kms_*` 변경은 없는 경우에는
이 라벨을 붙이지 않는다. 이 범위는 리소스 타입으로 정하며 파일명이나 문자열 검색으로 추측하지 않는다.

## 검사 기준

| 구분 | 판정 대상 |
| --- | --- |
| 변경 | 모든 KMS 리소스의 생성·갱신·삭제·교체와 import |
| 위험 | KMS 키 삭제 또는 교체, 활성 키의 비활성화 |
| 위험 | `bypass_policy_lockout_safety_check = true` |
| 위험 | `Allow`에서 조건 없이 `Principal: "*"` 또는 `Principal.AWS`의 `"*"` 허용 |
| 위험 | GuardDuty 서비스 주체의 사용 권한에 유효한 `aws:SourceAccount`·`aws:SourceArn` 제한 누락 |
| 위험 | 지원하지 않거나 누락된 plan JSON 형식 버전 |
| 확인 | 비활성 키 생성·설정, 지원되는 키의 자동 회전 비활성, 삭제 대기 기간 단축 |
| 확인 | 정책 본문이나 키 관리 설정이 plan에서 미확정, 정책 JSON 해석 불가 |
| 확인 | 조건부 와일드카드 주체 허용, AWS 서비스 주체에 `kms:*` 또는 `*` 허용 |

키 삭제·비활성화 검사는 AWS 생성 키, 외부 키 재료를 사용하는 키, 두 종류의 복제 키에 적용한다.
자동 회전은 `aws_kms_key`의 AWS 생성 대칭 암호화 키만 확인한다. 비대칭·HMAC·사용자 키 저장소·외부 키 재료는
자동 회전을 동일하게 적용할 수 없고, 복제 키의 회전은 주 키에서 관리한다.
[AWS KMS 키 회전](https://docs.aws.amazon.com/kms/latest/developerguide/rotate-keys.html)

삭제 대기 기간은 새로 임의의 최소값을 강제하지 않고 기존 값보다 짧아지는 변경을 보고한다.
키 삭제 예약 중에도 키를 사용할 수 없으며, 대기 기간은 삭제 취소를 위한 시간이다.
[AWS KMS 키 삭제](https://docs.aws.amazon.com/kms/latest/developerguide/deleting-keys.html)

## 키 정책 판정 범위

키 정책의 `Resource: "*"`는 해당 키를 뜻하므로 그 자체를 위험으로 판정하지 않는다.
계정 주체에 `kms:*`를 허용하는 기본 관리 권한 위임도 AWS 서비스에 전체 작업을 허용하는 규칙과 구분한다.
와일드카드 주체에 조건이 있어도 계정·역할을 실제로 제한하는지는 별도 확인 항목으로 남긴다.
[AWS KMS 키 정책](https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-overview.html)

GuardDuty의 `SourceAccount`는 `StringEquals`의 계정 ID를 확인하고, `SourceArn`은
`StringEquals`, `ArnEquals`, `StringLike`, `ArnLike`에 지정한 리전·계정·detector 경로를 확인한다.
조건의 이름만 있거나 값이 `*`, 빈 배열, 부정 조건이면 제한으로 인정하지 않는다.
리전별 GuardDuty 서비스 주체도 같은 규칙을 적용한다.
다른 AWS 서비스에는 이 두 조건을 일괄 강제하지 않는다. 서비스에 따라 encryption context 등 사용하는 조건이 다르다.
[GuardDuty findings 내보내기](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_exportfindings.html)

plan에서 정책 본문이 확정되지 않으면 위반이 없다고 추정하지 않고 확인 항목으로 표시한다.
정책을 별도 `aws_kms_key_policy`로 관리하면 키 리소스의 정책이 미확정으로 보일 수 있으므로 두 리소스를 함께 검토한다.
정책의 전체 유효 권한, 외부 계정의 IAM 권한, 데이터 보존 기간까지 자동으로 증명하는 검사는 아니다.

## 결과 수집과 실패 처리

기존 `conftest --all-namespaces --output json` 실행에서 KMS 판정도 함께 수집한다.
`iam-findings.json` 파일과 루트별 아티팩트 이름은 유지하며, IAM과 KMS 요약은 namespace로 구분한다.
KMS를 위한 별도 job이나 AWS API 호출은 추가하지 않는다.

plan 실패, 실패 표식, 아티팩트·판정 누락, KMS namespace 누락이 있으면 미검사로 표시하고 기존 라벨을 유지한다.
변경 영향이 없어 생략한 루트는 실패로 세지 않는다. 모든 루트의 plan을 생략한 커밋은
라벨을 정리하고 기존 코멘트만 검사할 변경이 없다는 내용으로 갱신한다.

코멘트에는 변경 수, 위험·확인 수와 최대 40개 판정을 표시하고 더 긴 목록은 실행 요약에 남긴다.
판정에는 식별용 리소스 주소와 검토 이유만 담는다. 키 재료, 정책 본문, `plan.json`, `tfplan`은
코멘트나 아티팩트에 올리지 않는다.

## 로컬 검증

```bash
conftest verify --policy .github/policy
node .github/scripts/test-kms-summary.js
node .github/scripts/test-plan-summary.js
```

Rego 테스트는 키 종류와 액션 조합, 정상·위험 정책, 회전 예외, 미확정 값과 import를 확인한다.
코멘트 테스트는 GitHub API를 모의 객체로 대체해 라벨 처리, namespace 분리와 결과 누락을 검증한다.
