# Velocirpator

`platform/velociraptor/`는 Velociraptor 서버와 이에 대한 IAM Role, 보안 그룹을 관리하며, state key는 `platform/velociraptor/terraform.tfstate`다.
`platform/network` tfstate의 VPC와 서브넷 출력을 읽으며, Wazuh와 동일한 VPC, 서브넷에 배치된다.

## Velociraptor EC2
| 구분 | 값 |
| :---: | :---: |
| instance_type | `t3.small`, 최소 권장 스펙 적용(2vCPU, 2GiB)|
| root_volume_size | `50 GB`, 최소 권장 디스크 용량 적용 |
| permissions_boundary_arn | Velociraptor EC2 역할에 붙이는 권한 경계 |
| iam_role_path_prefix | `/project/`, 실제 역할을 그 아래 `velociraptor/` 경로 |

## Outputs
Velocirpator Agent 통신을 위한 보안그룹 ID 출력(이후 Connectivity 모듈을 통해 VPC간 Agent 통신 보안그룹 정책 관리)

## IAM Policy
Velociraptor EC2 SSM 세션 접속 및 포트포워딩(관리자 대시보드 접속)을 위한 `/platform/wazuh` tfstate의 ssm_policy 활용

## Velociraptor 접속 방법
접속 방법은 [docs/runbooks/velociraptor.md](../../runbooks/velociraptor.md)를 따른다.