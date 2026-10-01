# RDS 상태 유지

중지한 RDS는 7일 뒤 AWS가 다시 켠다.
`.github/workflows/rds-state.yml`이 예약 실행으로 `platform/service-db`를 apply해
`db_state` 변수가 선언한 상태로 되돌린다.

## 언제 도는가

매일 03:00 KST에 돌고 `workflow_dispatch`로도 실행할 수 있다.
예약 실행은 기본 브랜치에서 돌아 OIDC subject가 `ref:refs/heads/main`이다. apply 역할의 신뢰 조건과 맞는다.

저장소에 60일간 활동이 없으면 GitHub가 예약 실행을 멈춘다. 그때는 수동으로 다시 켠다.

## 무엇을 하는가

1. apply 역할을 assume하고 루트를 init한다.
2. `terraform output -raw db_identifier`로 식별자를 읽고 `aws rds describe-db-instances`로 현재 상태를 조회해 실행 요약에 남긴다.
3. `-detailed-exitcode`로 plan을 돌린다. 변경이 없으면 apply하지 않는다.
4. 변경이 있으면 apply한다.

RDS가 자기 루트라서 `-target` 없이 루트 전체를 apply한다.
`db_state`가 `available`이면 드리프트가 없어 아무것도 하지 않으므로 항상 돌려도 안전하다.

현재 상태를 실행 요약에 남기는 이유는 자동 재시작이 언제 일어났는지 되짚기 위해서다.
plan만으로도 드리프트는 알 수 있다.

## main apply와 겹칠 때

`concurrency` 그룹이 `rds-state`로 따로 있어 취소되지 않는다.
state 잠금이 겹치면 `-lock-timeout=120s`로 기다린다.

## 비용

EC2와 RDS를 평일 09시부터 21시까지만 켜면 월 264시간이다.
인스턴스 시간 요금이 약 26 USD 줄어든다. EBS, ALB, RDS 스토리지는 그대로 나간다.
EventBridge가 아니라 GitHub 예약 실행을 쓰므로 AWS 쪽 추가 요금은 없다.
