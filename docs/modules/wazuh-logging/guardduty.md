# platform/guardduty

## 범위 (Scope)

GuardDuty 위협 탐지를 활성화하고, findings를 저장할 S3 버킷을 만들며,
Wazuh EC2가 그 findings를 읽을 수 있도록 IAM 권한을 연결한다.

- GuardDuty 감지기 활성화 (15분 주기로 findings 발행)
- findings 저장용 S3 버킷 생성
  - 퍼블릭 접근 차단
  - 버저닝 활성화 (실수 삭제/덮어쓰기 대비)
  - 30일 지난 이전 버전 자동 만료 (라이프사이클)
- findings 버킷 암호화용 KMS 키 생성 및 별칭 지정
- GuardDuty가 버킷에 findings를 쓸 수 있도록 버킷 정책 부여
- GuardDuty 감지기 → S3 버킷 publishing destination 연결
- Wazuh EC2가 findings 버킷/KMS 키를 읽을 수 있는 IAM 정책을 만들어
  `platform/wazuh`의 Wazuh Role에 연결

## 주의사항

- GuardDuty 감지기는 **계정 + 리전당 1개만 허용**된다.
  apply 전 반드시 아래 명령으로 기존 감지기 여부를 확인할 것.
```bash
  aws guardduty list-detectors --region ap-northeast-2
```
- S3 버킷 이름(`whs4-kintoun-guardduty-findings`)은 전역 유일해야 하므로
  계정 식별자를 접미사로 붙여 충돌을 방지했다.

## 의존 관계

`platform/wazuh`가 먼저 apply되어야 한다. `platform/wazuh`의 출력값
(`wazuh_role_name`, `wazuh_ec2_arn`)을 `terraform_remote_state`로 읽어
IAM 정책을 그 Role에 붙이기 때문이다.

## 입력 (Input Variables)

| 이름 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `project_name` | string | `"kintoun-secops-infra"` | 태그에 사용하는 프로젝트 이름 |

## 외부 참조 (Remote State)

| 참조 대상 | 출력값 | 용도 |
|---|---|---|
| `platform/wazuh` | `wazuh_role_name` | GuardDuty 읽기 권한을 붙일 IAM Role |
| `platform/wazuh` | `wazuh_ec2_arn` | S3/KMS 접근을 이 EC2 인스턴스로 제한하는 조건 |

## 출력 (Outputs)

현재 outputs.tf 없음 — 다른 루트가 이 모듈의 결과를 참조하지 않음.

## 생성되는 주요 리소스

- `aws_guardduty_detector.main`
- `aws_s3_bucket.guardduty_findings`
- `aws_kms_key.guardduty_findings` / `aws_kms_alias.guardduty_findings`
- `aws_iam_policy.guardduty_logging_wazuh`
- `aws_iam_role_policy_attachment.guardduty_logging_wazuh`