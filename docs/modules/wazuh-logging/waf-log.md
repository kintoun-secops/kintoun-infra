# wazuh-logging/waf-log

## 범위 (Scope)

- WAF 로그 저장용 S3 버킷 생성
  - 퍼블릭 접근 차단
  - 버저닝 활성화
  - 30일 지난 이전 버전 자동 만료 (라이프사이클)
- 버킷 정책: `delivery.logs.amazonaws.com`의 `s3:PutObject`, `s3:GetBucketAcl`을
  이 계정·리전으로 출처를 제한해서 허용 (`aws:SourceAccount`, `aws:SourceArn`)
- `platform/victim`이 만든 WAF Web ACL의 로깅 설정(`aws_wafv2_web_acl_logging_configuration`)을
  이 S3 버킷으로 연결하여 실제 WAF 로그 수집 활성화
- Wazuh EC2 Role에 이 버킷에 대한 `s3:GetObject`, `s3:ListBucket` 권한 부여
  (`platform/wazuh`가 만든 기존 Role을 재사용, 새 Role은 만들지 않음)

## 이번 범위에 포함되지 않은 것

`aws_wafv2_web_acl_logging_configuration`은 현재 코드에 주석처리되어 있어
이번 apply로 실제 WAF 로그 수집이 시작되지는 않는다.

## 입력 (Input Variables)

| 이름 | 설명 |
|---|---|
| `project_name` | 태그에 사용할 프로젝트 이름 |

## 외부 참조 (Remote State)

| 참조 대상 | 출력값 | 용도 |
|---|---|---|
| `platform/wazuh` | `wazuh_role_name` | WAF 로그 읽기 권한을 붙일 IAM Role |
| `platform/victim` | `waf_web_acl_arn` | WAF 로그 읽기 권한을 붙일 IAM Role |

## 출력 (Outputs)

없음 — 다른 root가 이 모듈의 결과를 참조하지 않음.