# Endpoint Agents

`platform/endpoint-agents/`는 관리형 노드에 auditd와 Wazuh Agent, Velociraptor Client를 설치하는
SSM 문서와 State Manager 연결을 관리하며, state key는 `platform/endpoint-agents/terraform.tfstate`다.
다른 루트의 출력을 읽지 않는다.

설치는 user_data가 아니라 SSM이 수행한다. 태그로 대상을 고르므로 나중에 같은 태그로 만든
인스턴스도 자동으로 포함되고, 이미 돌고 있는 인스턴스는 교체 없이 대상이 된다.

## 리소스

| 리소스 | 내용 |
| --- | --- |
| `aws_ssm_document.endpoint_agents` | `aws:runShellScript` Command 문서. 설치 스크립트 전체를 본문에 담는다 |
| `aws_ssm_association.endpoint_agents` | 태그 대상에 문서를 주기적으로 적용하는 State Manager 연결 |

문서 본문 한도는 64KB이고 현재 본문은 약 14.7KB다. 스크립트를 S3에 두지 않는다.
연결은 `max_concurrency = 1`로 한 대씩 실행해 패키지 저장소에 동시 요청을 보내지 않는다.
`max_errors = 100%`이므로 한 대가 실패해도 남은 대상은 계속 설치하며, 실패는 연결 실행 이력에 남는다.

## 입력

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `target_tag_key` | `EndpointAgents` | 설치 대상을 고르는 인스턴스 태그 키 |
| `target_tag_value` | `true` | 설치 대상을 고르는 인스턴스 태그 값 |
| `association_schedule` | `rate(30 minutes)` | 연결의 실행 주기 |
| `wazuh_manager` | `wazuh.internal.kintoun.work` | 등록과 로그 전송 대상 |
| `wazuh_agent_version` | `4.14.8-1` | 체크섬이 있는 버전만 쓸 수 있다 |
| `wazuh_agent_group` | `default` | 에이전트를 넣을 Wazuh 그룹 |
| `wazuh_base_url` | `https://packages.wazuh.com/4.x` | 패키지 내려받기 주소 |
| `velociraptor_version` | `0.77.2` | 체크섬이 있는 버전만 쓸 수 있다 |
| `velociraptor_base_url` | GitHub 릴리스 주소 | 바이너리 내려받기 주소 |

## Outputs

`document_name`, `association_id`, `target_tag`를 출력한다.

## 설치 대상 지정

인스턴스에 `EndpointAgents = "true"` 태그를 붙이면 대상이 된다. 태그 추가는 제자리 변경이므로
인스턴스를 교체하지 않는다. 현재 대상은 service-app의 frontend·backend·php와 attacker의 Kali다.

```hcl
tags = {
  Name           = "${var.project_name}-service-frontend"
  EndpointAgents = "true"
}
```

대상 인스턴스는 `AmazonSSMManagedInstanceCore`가 붙어 SSM 관리형 노드여야 하고, 443 아웃바운드가
열려 있어야 한다. `metadata_options`는 바꾸지 않는다. Kali는 user_data에서 `amazon-ssm-agent`를 직접 설치한다.
Wazuh는 1514(로그)과 1515(등록), Velociraptor는 8000이 매니저 쪽으로 열려 있어야 하며
`platform/connectivity`가 보안 그룹 사이의 규칙을 관리한다.

## 설치하는 것

| 구성 요소 | 받는 곳 | 서비스 |
| --- | --- | --- |
| auditd | 배포판 저장소 (deb `auditd`, rpm `audit`) | `auditd` |
| Wazuh Agent | `packages.wazuh.com` 의 deb·rpm 패키지 | `wazuh-agent` |
| Velociraptor Client | GitHub 릴리스 바이너리로 클라이언트 패키지를 만들어 설치 | `velociraptor_client` |

auditd는 Wazuh보다 먼저 설치한다. Wazuh가 `/var/log/audit/audit.log`를 읽기 때문이다.
감사 규칙은 추가하지 않고 배포판 기본 규칙을 그대로 쓴다.

## 배포판과 아키텍처 판별

스크립트가 인스턴스 안에서 `/etc/os-release`의 `ID`와 `ID_LIKE`로 패키지 계열을, `uname -m`으로
아키텍처를 정한다. 루트 모듈은 어떤 패키지를 받을지 지정하지 않는다.

| 계열 판별 | 아키텍처 | auditd 패키지 | Wazuh 패키지 | Velociraptor 바이너리 |
| --- | --- | --- | --- | --- |
| `debian`, `ubuntu` | `x86_64` | `auditd` | `wazuh-agent_<버전>_amd64.deb` | `linux-amd64` |
| `debian`, `ubuntu` | `aarch64` | `auditd` | `wazuh-agent_<버전>_arm64.deb` | `linux-arm64` |
| `rhel`, `fedora`, `centos`, `amzn` | `x86_64` | `audit` | `wazuh-agent-<버전>.x86_64.rpm` | `linux-amd64` |
| `rhel`, `fedora`, `centos`, `amzn` | `aarch64` | `audit` | `wazuh-agent-<버전>.aarch64.rpm` | `linux-arm64` |

현재 쓰는 AMI는 AL2023(`ID=amzn`, `ID_LIKE=fedora`), Ubuntu 24.04와 Kali(`ID_LIKE=debian`)다.
목록에 없는 배포판이나 아키텍처는 로그에 사유를 남기고 종료 코드 1로 끝낸다.

AL2023은 `audit`을 기본으로 포함하므로 auditd는 설치하지 않고 표식만 남긴다.
Ubuntu 24.04와 Kali는 기본에 없어 `apt-get`으로 설치한다. apt 캐시 갱신은 한 실행에서 한 번만 한다.

auditd는 서명된 배포판 저장소에서 받으므로 SHA256을 박지 않는다. 나머지 두 개는 모두 검사한다. 기대값은 `main.tf`의 `wazuh_sha256`과
`velociraptor_sha256`에 버전별로 적는다. 버전을 올리면 항목을 함께 더해야 하며,
없는 버전을 지정하면 plan이 실패한다. 값은 공개 배포 파일에서 계산한다.

```bash
curl -sfL https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.14.8-1_amd64.deb | sha256sum
```

## 에이전트 이름

Wazuh 에이전트 이름은 `<인스턴스 이름>-<등록 시각 UTC>`다. 인스턴스 이름은 IMDS에서 아래 순서로 찾는다.

| 순서 | 출처 | 조건 |
| --- | --- | --- |
| 1 | `meta-data/tags/instance/Name` | `instance_metadata_tags`가 `enabled` 일 때만 |
| 2 | `meta-data/instance-id` | IMDS는 읽히지만 태그가 노출되지 않을 때 |
| 3 | `hostname` | 메타데이터 자체를 읽을 수 없을 때 |

이 저장소는 모든 인스턴스에서 `instance_metadata_tags`를 `disabled`로 둔다. 따라서 실제로 쓰이는
것은 두 번째 줄이고 이름은 인스턴스 ID로 만들어진다.

```text
i-0abc1234567890abc-20261012T142233Z
```

인스턴스 ID는 EC2 레코드와 1:1로 대응하고 재사용되지 않으므로, 이름이 바뀔 수 있는 Name 태그보다
사후 추적에는 오히려 분명하다. Name 태그를 쓰려면 대상 인스턴스의 `instance_metadata_tags`를
`enabled`로 바꾸거나, 인스턴스 역할에 `ec2:DescribeTags`를 더해야 한다. 전자는 그 인스턴스 자신의
태그만, 후자는 계정 전체의 태그를 노출한다.

첫 번째 줄의 조회는 태그가 꺼져 있으면 404로 끝나고 두 번째 줄로 넘어간다. 나중에 특정 인스턴스에서
태그를 켜면 코드를 고치지 않고 Name 태그가 쓰인다. Wazuh 이름에 쓰지 않는 문자는 하이픈으로 바꾼다.

Wazuh는 등록 이후 에이전트 이름을 바꿀 수 없다. 교체한 인스턴스는 매니저에 새 에이전트로 보이며
이전 에이전트는 남는다. 정리는 매니저에서 수행한다.

Velociraptor Client는 이름으로 식별하지 않는다. 최초 실행에서 만든 client ID를
`/etc/velociraptor.writeback.yaml`에 저장하고 그 값을 계속 쓴다.

## 반복 실행

연결은 주기마다 같은 스크립트를 다시 돌린다. 스크립트가 먼저 설치 상태를 확인하므로
재실행은 아래 세 가지만 한다.

| 상태 | 처리 |
| --- | --- |
| 표식이 있다 | 설치를 건너뛴다 |
| 표식은 없고 이미 깔려 있다 | 설치하지 않고 표식만 남긴다 (`adopted=yes`) |
| 서비스가 멈춰 있다 | `systemctl enable --now`로 다시 올린다 |

세 구성 요소를 각각 따로 판단하므로 빠진 것만 설치한다. 셋 다 표식이 있으면 서비스 상태만
확인하고 끝낸다. 내려받기가 필요한 구성 요소가 없으면 `curl`도 챙기지 않는다.

표식은 루트 볼륨의 `/var/lib/kintoun-agents/`에 남는다. 손으로 설치한 인스턴스를 다시 설치하지
않는 것은 두 번째 줄 덕분이다. 실행 기록은 `/var/log/kintoun-agents.log`와 SSM 실행 출력에 함께 남는다.

| 파일 | 내용 |
| --- | --- |
| `/var/lib/kintoun-agents/auditd` | 설치 또는 입양 여부 |
| `/var/lib/kintoun-agents/wazuh` | 등록한 에이전트 이름, 매니저, 버전 |
| `/var/lib/kintoun-agents/velociraptor` | 설치한 버전 |

## 등록 시점

State Manager는 노드가 SSM에 등록된 뒤 연결을 적용한다. user_data와 달리 부팅 즉시가 아니며
새 인스턴스는 최대 한 주기(기본 30분)까지 기다릴 수 있다. 더 빨라야 하면
`association_schedule`을 줄인다.

실행 결과는 Systems Manager 콘솔의 State Manager 또는 다음 명령으로 확인한다.

```bash
aws ssm describe-association-executions \
  --association-id "$(terraform -chdir=platform/endpoint-agents output -raw association_id)" \
  --profile kintoun-admin
```

## Velociraptor client 설정

`files/velociraptor-client.config.yaml`은 서버가 `velociraptor config client`로 내놓은 파일이다.
서버 주소와 CA 인증서, nonce만 들어 있고 CA 비밀키는 없다. 설치할 때 이 파일을 넣어
클라이언트 패키지를 만든다.

서버의 CA가 바뀌면 이 파일을 함께 바꿔야 한다. 서버에는
`/root/velociraptor-client.config.yaml`에 같은 내용이 있다. 추출 절차는
[Velociraptor 접속 방법](../../runbooks/velociraptor.md)을 따른다.
