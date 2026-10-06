# Uptime Kuma

`platform/uptime-kuma/`는 Uptime Kuma 서버 EC2와 데이터 EBS, IAM Role, 보안 그룹을 관리합니다.
state key는 `platform/uptime-kuma/terraform.tfstate`입니다.
`platform/network` state의 VPC와 서브넷, `platform/wazuh` state의 SSM 정책을 읽으며 Wazuh, Velociraptor와 같은 CERT 서브넷에 배치됩니다.

## Uptime Kuma EC2

| 변수 | 기본값 |
| --- | --- |
| `instance_type` | `t3.small` |
| `root_volume_size` | `20` GB |
| `data_volume_size` | `10` GB |
| `uptime_kuma_image` | `louislam/uptime-kuma:2.5.5` (digest 고정) |
| `iam_role_path_prefix` | `/project/`, 역할은 그 아래 `uptime-kuma/` 경로에 생성됩니다 |

user data가 Docker를 설치하고 `uptime-kuma` systemd 서비스로 컨테이너를 실행합니다.
대시보드는 인스턴스의 `127.0.0.1:3001`에만 열리며 SSM 포트포워딩으로 접속합니다.
모니터 설정과 기록은 데이터 EBS의 `/data/uptime-kuma`에 저장되므로 인스턴스를 교체해도 유지됩니다.
데이터 EBS에는 `prevent_destroy`가 설정되어 있습니다.

`uptime_kuma_image`를 바꿔도 `user_data_replace_on_change = false`이므로 실행 중인 인스턴스에는 반영되지 않습니다.

## 보안 그룹

아웃바운드는 TCP 443만 허용합니다. CERT 서브넷의 인터넷 경로인 NAT 인스턴스도 443만 허용하므로 외부 대상은 HTTPS 모니터만 동작합니다.
다른 VPC나 다른 보안 그룹의 대상을 모니터링하려면 대상 쪽 인바운드 규칙과 이 보안 그룹의 아웃바운드 규칙을 추가해야 합니다.

## Outputs

| 출력 | 값 |
| --- | --- |
| `uptime_kuma_instance_id` | 포트포워딩 대상 인스턴스 ID |
| `uptime_kuma_sg_id` | Uptime Kuma 보안 그룹 ID |

## 접속 권한

별도 사용자 정책을 만들지 않습니다. 인스턴스에 `SSMPortForward = "true"` 태그를 붙여 identity 루트의 `kintoun-secops-infra-ssm-port-forwarding` 정책 대상에 포함합니다.
셸 접속용 `SSMShell` 태그는 붙이지 않습니다.

접속 방법은 [Uptime Kuma 접속 방법](../../runbooks/uptime-kuma.md)을 참고합니다.
