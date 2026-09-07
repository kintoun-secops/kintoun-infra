# Platform

`platform/`은 Wazuh 서버와 공유 네트워크, 서비스 IAM을 관리한다.
state key는 `platform/terraform.tfstate`다.

| 관리하는 것 | 현재 구현 밖의 것 |
| --- | --- |
| VPC, Internet Gateway, 퍼블릭 서브넷·라우팅 | victim·attacker·logging 루트 |
| Wazuh All-in-one EC2와 암호화된 루트 EBS | Wazuh 데이터 전용 EBS와 자동 복구 |
| EC2 역할·인스턴스 프로파일·SSM 정책 | 팀원 IAM User와 기존 그룹 생성 |
| 그룹의 포트 포워딩·AWS 로그인 정책 연결 | Shell 정책의 사용자·그룹 연결 |

## 기본 구성

| 입력 | 기본값 또는 역할 |
| --- | --- |
| `project_name` | `kintoun-secops-infra` |
| `vpc_cidr` | `10.50.0.0/16` |
| `public_subnet_cidrs` | `10.50.10.0/24` |
| `instance_type` | `m6i.large` |
| `root_volume_size` | `100` GiB |
| `permissions_boundary_arn` | EC2 IAM 역할의 권한 경계 |
| `iam_role_path_prefix` | `/project/`. Wazuh 역할은 그 아래 `wazuh/` 경로 |
| `port_forwarding_group_names`, `aws_login_group_names` | 기존 팀 그룹에 정책 연결 |

EC2는 SSM Parameter Store에서 Amazon Linux 2023 x86_64 AMI를 조회한다.
IMDSv2를 강제하며 gp3 루트 EBS는 IOPS 3000, 처리량 125 MiB/s, 암호화를 사용한다.
기본 정책 연결 대상은 `WHS4_Infra`, `WHS4_Attack`, `WHS4_SIEM_Detect`다.
그룹은 사전에 존재해야 한다.

## Wazuh 설치와 수명 주기

`platform/scripts/wazuh-install.sh`가 최초 부팅 시 Wazuh 4.14 계열 설치 스크립트를
받아 All-in-one 설치를 실행한다. Manager, Indexer, Dashboard, Filebeat가 모두
활성 상태인지 확인한 후 `/var/lib/wazuh-bootstrap/complete`를 기록한다.
로그는 root만 읽는 `/var/log/wazuh-bootstrap.log`에 남긴다.

`user_data_replace_on_change = false`이므로 스크립트를 고쳤다고 기존 서버가
교체되거나 설치가 자동으로 다시 실행되지는 않는다. 업그레이드는 별도 운영 작업이다.

최신 AMI 값과 `associate_public_ip_address` 차이는 `ignore_changes`로 제외한다.
중지된 인스턴스의 공인 IP 속성 차이로 인한 교체를 막는 설정이며, 다른 속성의
변경까지 교체를 막아 주지는 않는다. 항상 plan의 replace/destroy를 검토한다.

`delete_on_termination = false`로 EC2 종료 뒤 루트 볼륨을 보존한다.
교체 시에는 새 볼륨이 생기므로 기존 데이터 복구는
[Wazuh 복구 절차](../runbooks/wazuh.md#ec2-교체와-ebs-복구)를 따른다.

## 출력 계약

| 출력 | 소비 목적 |
| --- | --- |
| `wazuh_instance_id` | SSM 세션 대상 |
| `ssm_port_forward_command` | Dashboard 포트 포워딩 명령 |
| `wazuh_dashboard_url` | 터널 연결 후 로컬 Dashboard 주소 |
| `wazuh_role_name`, `wazuh_ec2_arn` | 후속 로깅 정책 연결 및 대상 식별 |
| `main_vpc_id`, `main_igw_id` | 후속 실습 루트의 공유 네트워크 |
| `ssm_policy_arn` | 후속 EC2 역할의 SSM 정책 연결 |
| `wazuh_sg_agent_id` | 후속 agent 통신 규칙 설계 |

출력을 소비하는 새 루트는 매니페스트의 `depends_on`에 `platform`을 등록한다.
자세한 규칙은 [개발 규칙](../conventions.md)에 있다.
