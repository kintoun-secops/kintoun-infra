# Platform state 이전

이 문서는 network와 Wazuh state를 분리하던 시점의 절차와 복구 기준을 기록한다.
아래의 사용자 권한 9개는 당시 정책 3개와 그룹 연결 6개를 합한 수다.
분리 이후 그룹 연결은 코드에서 제거했으므로 현재 구성은 [Platform](../modules/platform.md)을 기준으로 확인한다.

기존 platform에서 공유 네트워크 5개와 Wazuh 인프라 8개를 새 루트로 옮긴다.
사용자 정책 3개와 그룹 정책 연결 6개는 기존 platform에 유지한다.
사용자 IAM의 최종 소유자는 identity지만, 그 이전은 별도 담당 작업이며 이 PR에 포함하지 않는다.
AWS 리소스는 재생성하지 않고 state의 관리 위치만 옮긴다.

!!! warning "적용은 CI에서만 수행합니다"
    이 이전 PR에서는 로컬에서 `apply`, `import`, `state mv`, `state push`를 실행하지 않습니다.
    PR plan을 확인한 뒤 main에 병합하고, CI가 network, Wazuh, 기존 platform 순서로 적용합니다.
    운영자 자격증명은 읽기 전용 plan과 state 백업에만 사용합니다.

## 범위와 적용 순서

| Wave | 루트 | 이전 동작 |
| --- | --- | --- |
| 먼저 | `platform/network` | 네트워크 5개 import |
| 같은 wave | `identity` | 기존과 같이 독립 실행. 변경 없음 |
| 다음 | `platform/wazuh` | EC2, 보안 그룹, 인프라 IAM 8개 import |
| 마지막 | 기존 `platform` | 이전 13개만 삭제 없이 관리 해제. 사용자 권한 9개와 기존 출력 유지 |

리소스 주소는 유지한다. import ID는 새 루트의 `imports.tf`에 기록한다.
라우팅 테이블 연결은 `subnet-id/route-table-id`, IAM 역할 정책 연결은
`role-name/policy-arn` 형식을 사용한다.
현재 서브넷에는 기존 Wazuh EC2가 연결되어 있으므로 network도 재생성하지 않고 import한다.

## 첫 PR에서 remote state 읽기

분리 당시 PR은 모든 루트를 plan하므로 아직 생성되지 않은 network와 wazuh state를 읽을 수 없다.
apply 순서만 지정해도 이 문제는 해결되지 않는다.

Wazuh와 기존 platform의 `migration.tf`는 S3에서 생산자의 정확한 state key가 있는지 확인한다.
state가 없을 때만 백업에서 확인한 ID와 ARN을 사용한다.
`.tflock`만 있는 경우도 state가 없는 것으로 판단한다.
생산자 state가 있으면 반드시 `terraform_remote_state` 출력을 사용한다.
S3 조회 실패, 읽기 권한 오류, 기존 state의 출력 누락은 plan 오류로 처리한다.

이 값은 첫 import를 위한 이전 시점의 식별자다. 새 리소스를 찾기 위한 태그나 이름 조회가 아니다.
새 루트를 재사용하거나 기존 리소스를 교체하기 전에는 import 블록과 이 이전 경로를 함께 검토한다.
기존 platform의 출력도 같은 방식으로 새 state를 참조하여 기존 소비자의 계약을 유지한다.

!!! info "import는 리소스를 다시 만들지 않습니다"
    `import` 블록은 기존 AWS 리소스를 새 state에 등록합니다.
    기존 platform의 `removed` 블록은 원래 state에서 관리만 해제하며 `destroy = false`로 삭제를 막습니다.

## 검증과 복구 지점

이전 전 platform plan이 `No changes`인지 확인하고 state를 저장소 밖에 백업한다.
로컬 관리자 자격증명은 읽기 전용 plan과 state 조회에 사용한다.
plan은 `-lock=false`로 실행하고 `-out`과 출력 파일 저장을 사용하지 않는다.
state 백업에는 민감값이 있을 수 있으므로 Git이나 CI 아티팩트에 올리지 않는다.
S3 버전 관리도 복구 수단이며 이전 버전의 보존 기간은 30일이다.

| PR plan | 합격 기준 |
| --- | --- |
| network | `5 to import, 0 to add, 0 to change, 0 to destroy` |
| wazuh | `8 to import, 0 to add, 0 to change, 0 to destroy` |
| 기존 platform | 13개가 `will no longer be managed`이며 `will not be destroyed`. 추가, 변경, 삭제 0개 |
| identity | `No changes` |
| IAM 가드 | `[차단]` 없음 |

특히 Wazuh EC2에 in-place 변경이나 교체가 없어야 한다.
설치 스크립트, 루트 EBS 보존 설정, 서비스 IAM 정책 본문을 함께 확인한다.

머지 후 main CI의 계산된 모든 wave가 성공해야 한다.
다음 plan에서 네 루트가 모두 `No changes`인지 확인한다.
network와 wazuh의 managed 리소스 13개, 기존 platform의 사용자 권한 9개를 합쳐
이전 platform의 22개 주소와 비교한다. identity는 별도로 변경 없음인지 확인한다.
기존 platform의 출력값이 그대로인지, 동일 EC2와 EBS가 유지되는지,
기존 사용자 프로필로 SSM 대시보드 접속이 되는지도 확인한다.

## 실패와 롤백

적용 전에는 PR을 닫으면 된다. 이미 적용된 state 이동은 Git 변경만 되돌려서는 복구되지 않는다.
import 완료 여부를 확인하지 않고 새 루트의 리소스 블록을 삭제하면 실제 자원 삭제가 계획될 수 있다.

1. 실행 중인 apply가 끝난 뒤 각 루트의 plan과 state를 확인한다.
2. network나 wazuh에서 실패했다면 기존 platform은 아직 이전 대상을 관리한다.
   성공한 새 state에는 일부가 중복 등록되어 있을 수 있다. 원인을 고치고 main CI를 재실행하는 것이 우선이다.
3. 이 단계에서 되돌리려면 기존 platform 선언을 복원하고, 새 루트에 가져온 리소스만
   `removed { lifecycle { destroy = false } }`로 바꾸는 복구 PR을 준비한다.
   두 state에서 동시에 같은 자원을 변경하지 않도록 plan을 확인한다.
4. 기존 platform의 관리 해제까지 끝난 뒤 되돌리려면 기존 선언과 13개의 import 블록을 함께 복원한다.
   기존 platform이 먼저 import하고 이후 새 루트가 `destroy = false`로 관리 해제하도록
   매니페스트 순서를 반대로 조정한다. 단순 revert는 리소스 재생성을 계획할 수 있으므로 사용하지 않는다.
5. 복구 PR도 추가, 변경, 삭제 없이 필요한 import와 관리 해제만 계획되는지 확인한 후 CI로 적용한다.

현재 PR은 import, removed 블록과 기존 platform backend를 유지한다.
기존 platform state에는 사용자 권한이 남으므로 삭제하지 않는다.
그 state의 정리는 별도 사용자 권한 이전이 끝난 뒤 진행한다.
state 복원은 [State와 장애 대응](terraform.md#state-복구)을 따른다.

!!! danger "단순 revert로 state 이전을 되돌리지 않습니다"
    apply가 일부 wave까지 진행된 뒤에는 Git 커밋만 되돌리면 리소스가 이중 관리되거나 삭제될 수 있습니다.
    각 루트의 state와 plan을 확인한 뒤 import와 `removed` 블록을 반대 순서로 구성한 복구 PR을 사용합니다.

공식 동작은 [Terraform state 리팩터링](https://developer.hashicorp.com/terraform/language/state/refactor)과
[remote state 데이터 소스](https://developer.hashicorp.com/terraform/language/state/remote-state-data)에 있다.
