# Wazuh

`platform/wazuh/`는 Wazuh All-in-one 서버와 인프라 IAM을 관리한다.
state key는 `platform/wazuh/terraform.tfstate`다.
`platform/network`의 VPC와 서브넷 출력을 읽으며 wave1에서 적용한다.

| 관리하는 것 | 다른 루트에서 관리하는 것 |
| --- | --- |
| Wazuh EC2와 암호화된 루트 EBS | 공유 VPC와 서브넷 |
| 매니저 보안 그룹과 에이전트 보안 그룹 | 사용자 SSM 접속 정책과 그룹 연결 |
| EC2 IAM 역할과 인스턴스 프로파일 | 사용자 AWS CLI 로그인 권한 |
| EC2가 SSM과 통신하는 서비스 정책 | 후속 logging 및 lab 인프라 |

## 입력

| 입력 | 기본값 또는 용도 |
| --- | --- |
| `project_name` | `kintoun-secops-infra` |
| `instance_type` | `m6i.large` |
| `root_volume_size` | `100` GiB |
| `permissions_boundary_arn` | Wazuh EC2 역할에 붙이는 권한 경계 |
| `iam_role_path_prefix` | `/project/`. 실제 역할은 그 아래 `wazuh/` 경로 |

## 설치와 수명 주기

`platform/wazuh/files/wazuh-install.sh`가 첫 부팅에 Wazuh 4.14 계열 설치를 실행한다.
이전 전 `platform/scripts/wazuh-install.sh`와 바이트가 동일하다.
Manager, Indexer, Dashboard, Filebeat를 확인한 뒤 `/var/lib/wazuh-bootstrap/complete`를 기록한다.
로그는 root만 읽는 `/var/log/wazuh-bootstrap.log`에 남는다.

AMI와 `associate_public_ip_address` 차이는 기존과 같이 `ignore_changes`로 제외한다.
`user_data` 자체는 무시하지 않는다. 설치 스크립트 변경을 서버 운영 작업과 분리해서 검토한다.
`user_data_replace_on_change`는 기본값 false를 사용한다.

IMDSv2를 강제한다. gp3 루트 EBS는 암호화하며 IOPS 3000, 처리량 125 MiB/s를 사용한다.
`delete_on_termination = false`로 EC2 종료 후에도 루트 EBS를 보존한다.
기존 루트 볼륨의 Name 태그를 `root_block_device.tags`로 관리하여 import 때 태그 변경을 피한다.

`wazuh_sg`는 inbound 규칙 없이 outbound TCP 443만 허용한다.
`wazuh_sg_agent`는 생성과 출력만 하며 현재 통신 규칙과 인스턴스 연결은 없다.
후속 agent 연동 때 이 루트에 매니저의 1514, 1515/TCP 허용 규칙을 추가하고,
lab은 에이전트 보안 그룹 ID를 받아 인스턴스에 연결한다.

## 출력

| 출력 | 용도 |
| --- | --- |
| `wazuh_instance_id` | SSM 세션 대상 |
| `ssm_port_forward_command`, `wazuh_dashboard_url` | 대시보드 접속 |
| `wazuh_ec2_arn` | 기존 platform의 사용자 접근 정책 대상 |
| `wazuh_role_name`, `wazuh_role_arn` | 후속 logging 루트의 서비스 정책 연결 |
| `ssm_policy_arn` | 후속 EC2 역할의 SSM 서비스 정책 연결 |
| `wazuh_sg_id`, `wazuh_sg_agent_id` | 매니저 및 에이전트 보안 그룹 참조 |

후속 logging 루트는 기존 `platform/terraform.tfstate` 대신 이 state를 읽는다.
소비자는 매니페스트에 `depends_on: ["platform/wazuh"]`를 등록한다.
첫 이전 plan의 state 참조 방식은 [Platform state 이전](../../runbooks/platform-migration.md)에 있다.
운영 절차는 [Wazuh 접속 및 복구](../../runbooks/wazuh.md)를 따른다.
