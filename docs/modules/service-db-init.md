# Service DB Init

`service-db-init/`는 데이터베이스 안의 사용자와 권한을 관리한다.
state key는 `service-db-init/terraform.tfstate`다.

`bootstrap`처럼 사람이 로컬에서 apply한다. RDS가 프라이빗 서브넷에 있어 CI 러너가 닿지 않으므로
매니페스트에 등록하지 않고 `tf-roots.js`의 제외 목록에 둔다.

| 관리하는 것 | 다른 루트에서 관리하는 것 |
| --- | --- |
| IAM 인증 사용자와 `rds_iam` 부여 | RDS 인스턴스와 파라미터 그룹 |
| 데이터베이스와 스키마 권한 | 백엔드 EC2와 `rds-db:connect` 정책 |

접속 정보는 `platform/service-db`의 출력에서 읽는다.
마스터 비밀번호는 `ephemeral`로 읽어 state와 plan 파일에 남기지 않는다.

앱이 자기 유저로 마이그레이션을 돌려 테이블 소유자가 되므로 스키마에 `CREATE`를 준다.
PostgreSQL 15부터 `public` 스키마가 `PUBLIC`에 `CREATE`를 주지 않는다.

## 선행 조건

세 가지가 갖춰져야 실행할 수 있다.

1. `service-db-port-forwarding` 과 `service-db-master-secret-read` 정책이 `identity/groups.yaml` 로
   그룹에 붙어 있다. 앞은 터널을 열고 뒤는 마스터 비밀번호를 읽는다.
2. `platform/service-app` 과 `platform/service-db` 를 로컬에서 `terraform init` 했다.
   아래 명령이 그 출력을 읽는다.
3. `session-manager-plugin` 이 설치되어 있다.

## 적용

터미널 두 개를 쓴다. 저장소 최상위에서 시작한다.

첫 터미널에서 백엔드 EC2 를 거치는 터널을 연다.

```bash
aws ssm start-session \
  --target "$(terraform -chdir=platform/service-app output -raw backend_instance_id)" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "host=$(terraform -chdir=platform/service-db output -raw db_endpoint),portNumber=5432,localPortNumber=15432"
```

두 번째 터미널에서 apply 한다.

```bash
cd service-db-init
terraform init
terraform apply -var-file=example.tfvars
```

`plan`도 프로바이더가 접속하므로 터널이 열려 있어야 한다.

VPC 안에서 직접 돌린다면 `-var-file`을 빼면 RDS 엔드포인트로 붙는다.

## 입력

| 입력 | 기본값 |
| --- | --- |
| `db_host_override` | 비어 있음. 터널을 쓰면 `127.0.0.1` |
| `db_port_override` | 비어 있음. 터널을 쓰면 `15432` |

터널로 붙으면 주소가 `127.0.0.1`이라 인증서 호스트 이름이 맞지 않는다.
`sslmode`는 `require`로 두어 암호화는 하고 이름 검증은 하지 않는다.
