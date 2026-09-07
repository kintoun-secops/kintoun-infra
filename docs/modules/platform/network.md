# Network

`platform/network/`는 공유 VPC와 Wazuh 매니저용 퍼블릭 서브넷을 관리한다.
state key는 `platform/network/terraform.tfstate`이며 매니페스트의 wave0에서 적용한다.

| 관리하는 것 | 다른 루트에서 관리하는 것 |
| --- | --- |
| VPC와 Internet Gateway | Wazuh 호스트와 보안 그룹 |
| 퍼블릭 서브넷과 라우팅 테이블, 연결 | EC2 서비스 역할과 사용자 접근 정책 |

## 입력

| 입력 | 기본값 |
| --- | --- |
| `project_name` | `kintoun-secops-infra` |
| `vpc_cidr` | `10.50.0.0/16` |
| `public_subnet_cidrs` | `["10.50.10.0/24"]` |

서브넷의 자동 공인 IP 할당은 꺼져 있다. 기본 경로는 Internet Gateway로 향한다.
기존 `aws_subnet.public_subnet[0]` 주소를 유지한다.

## 출력

| 출력 | 용도 |
| --- | --- |
| `main_vpc_id`, `main_igw_id` | 기존 출력 이름을 유지한 VPC와 Internet Gateway ID |
| `vpc_cidr` | 공유 VPC의 주소 범위 |
| `manager_subnet_id` | Wazuh 매니저가 사용하는 첫 번째 서브넷 ID |
| `public_subnet_ids` | 인덱스 순서의 서브넷 ID 목록 |
| `public_route_table_id` | 퍼블릭 서브넷 라우팅 테이블 ID |

소비자는 이 state의 출력을 읽고 `depends_on`에 `platform/network`를 등록한다.
향후 lab과 ALB 서브넷은 용도에 맞는 출력을 추가한다.
