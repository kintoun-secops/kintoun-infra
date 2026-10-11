# Service CI DB

`platform/service-ci-db/`는 CI 서비스만 쓰는 PostgreSQL을 관리한다.
state key는 `platform/service-ci-db/terraform.tfstate`이며 `platform/service-network` 다음에 적용한다.
`platform/service-network`의 VPC와 보안 그룹 출력을 읽는다.

개인정보를 다루는 CI 서비스의 데이터를 [Service DB](service-db.md)와 물리적으로 분리하려고 인스턴스를 따로 둔다.
마스터 시크릿, 스토리지 암호화 키, 스냅샷, 보안 그룹이 모두 별개다.

| 관리하는 것 | 다른 루트에서 관리하는 것 |
| --- | --- |
| RDS 인스턴스와 파라미터 그룹 | VPC, 프라이빗 서브넷, 보안 그룹 |
| DB 서브넷 그룹 | CI EC2와 IAM 역할 |
| 스토리지 암호화 KMS 키 | 데이터베이스 사용자 |
| 인스턴스 상태 리소스 | |

## 접속 방식

CI는 `ci` 사용자의 비밀번호로 접속한다. IAM 데이터베이스 인증은 끄고, CI 인스턴스 롤에 `rds-db:connect`를 주지 않는다.
비밀번호는 Terraform 코드와 인스턴스 user_data에 없다. `service-ci` 저장소의 GitHub 시크릿 `DB_PASSWORD`에 등록하고,
배포 워크플로가 릴리스 아티팩트의 `.env`에 써서 보낸다. 앱은 `run.sh`가 `.env`를 읽어 `DB_PASSWORD` 환경 변수로 받는다.
같은 값이 [Service CI DB Init](../service-ci-db-init.md)의 `ci_db_password` 입력으로 데이터베이스 사용자에 설정된다.

스토리지, 스냅샷, 자동 백업은 이 루트의 KMS 키(`alias/<프로젝트>-service-ci-db-storage`)로 암호화한다.
키는 자동 회전하고 삭제 대기 기간은 30일이다.

파라미터 그룹에서 `rds.force_ssl`을 1로 두어 평문 연결을 막는다.

마스터 비밀번호는 `manage_master_user_password`로 AWS가 Secrets Manager에 보관하고 교체한다.
사용자 생성과 권한 부여에만 쓴다. 시크릿 하나당 월 0.40 USD가 든다.

## 인스턴스 상태

중지한 RDS는 7일 뒤 AWS가 다시 켠다.
`aws_rds_instance_state`가 `db_state` 변수를 따르고, 예약 워크플로가 이 루트를 주기적으로 apply해
선언한 상태로 되돌린다. 자세한 내용은 [RDS 상태 유지](../../ci/rds-state.md)에 있다.

## 입력

| 입력 | 기본값 |
| --- | --- |
| `db_instance_class` | `db.t4g.micro` |
| `db_allocated_storage` | `20` |
| `db_max_allocated_storage` | `100` |
| `db_name` | `cidb` |
| `db_master_username` | `dbadmin` |
| `db_iam_user` | `ci` |
| `db_multi_az` | `false` |
| `db_backup_retention_days` | `7` |
| `db_state` | `available` |

## 출력

| 출력 | 용도 |
| --- | --- |
| `db_endpoint`, `db_port`, `db_name`, `db_iam_user` | CI 환경 변수 |
| `db_identifier` | 예약 워크플로의 상태 조회 |
| `db_master_secret_arn` | 마스터 비밀번호 시크릿 |
| `master_secret_read_policy_arn` | `identity/groups.yaml` 의 `policy_arns` 에 등록 |

## 적용 후 할 일

데이터베이스 안의 사용자와 권한은 [Service CI DB Init](../service-ci-db-init.md)이 관리한다.
Terraform은 데이터베이스 내부를 인스턴스 루트에서 다루지 않는다.
