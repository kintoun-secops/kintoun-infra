# State와 장애 대응

## State 위치와 권한

모든 루트는 `kintoun-tfstate` 버킷의 `<루트>/terraform.tfstate`를 사용한다.
잠금은 같은 key 뒤에 `.tflock`을 붙인 객체다. 운영자가 버킷 이름을 바꿨다면
각 `backend.tf`의 값을 기준으로 확인한다.

CI는 state를 읽고 쓰되 삭제할 수 없고, 잠금 객체는 생성·삭제할 수 있다.
bootstrap 역할·OIDC·보호 정책의 변경은 운영자 자격증명으로 수행한다.

## Plan 또는 apply 실패

1. 실패한 루트와 단계(`init`, `plan`, 정책 검사, `apply`)를 Actions에서 확인한다.
2. `init` 실패라면 버킷·key·권한·잠금을, OIDC 실패라면 저장소 변수와 trust subject를 확인한다.
3. 매니페스트 오류라면 `node .github/scripts/tf-roots.js`로 경로·key·의존성을 확인한다.
4. 인프라 변경 실패라면 실제 자원과 state를 확인하고 수정 PR을 준비한다.
5. 수정이 main에 반영된 후 적용을 확인한다. 재실행이 필요하면 main의 terraform apply를 사용한다.

apply 중 실패한 루트는 일부 자원이 이미 바뀌었을 수 있다. 다른 루트의 성공도 유지된다.
현재 상태를 다시 plan한 뒤 진행한다.

## 남은 잠금 해제

다른 plan/apply가 실행 중이면 잠금을 해제하지 않는다. Actions와 운영자의 실행이
모두 종료되었고 잠금 소유자가 없음을 확인한 뒤 오류에 표시된 lock ID로 해제한다.

```bash
AWS_PROFILE=kintoun-admin terraform -chdir=<루트> force-unlock <lock-id>
```

이후 plan을 다시 실행한다. `.tflock`의 수동 삭제보다 Terraform의 잠금 해제 명령을 사용한다.

## State 복구

S3 버전 관리가 과거 버전을 보존하지만 현재 수명 주기 정책은 이전 버전을 30일 후 만료시킨다.
state 자체는 인프라 데이터의 백업을 대신하지 않는다.

1. 해당 state를 사용하는 모든 실행을 중지하고 현재 객체 버전·수정 시각을 기록한다.
2. 사고 직전의 S3 객체 버전을 확인하고 제한된 운영 환경에서 현재 state와 비교한다.
3. 실제 AWS 자원과 일치하는 복구 방식을 정한다. 과거 state 복원이나 import가 필요한지 검토한다.
4. 운영자 권한으로 복구하고 plan에서 의도하지 않은 삭제·교체가 없는지 확인한 뒤 CI를 재개한다.

state에는 민감값이 포함될 수 있으므로 다운로드한 파일을 저장소나 문서 아티팩트에 넣지 않는다.
state 수동 편집이나 오래된 버전의 무조건 덮어쓰기는 자원 추적을 깨뜨릴 수 있다.
