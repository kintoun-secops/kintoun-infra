# VPC 피어링
`platform/connectivity/`는 서비스 VPC <-> CERT VPC 간의 피어링과 라우팅, Agent 통신을 위한 보안그룹 정책을 관리한다.
<br/>state key는 `platform/connectivity/terraform.tfsate`다.
<br/>`platform/network`, `platform/service-network` VPC와 서브넷, 라우트 테이블, Agent용 보안그룹 ID 출력을 읽는다.

⭐️ 각 모듈의 VPC가 선행되어 생성된 이후, `apply` 한다.

## 피어링 구조
```mermaid
flowchart LR
    subgraph VPC2["서비스 VPC 10.60.0.0/16"]
        subgraph Sub2["Public Subnet 10.60.10.0/24"]
            WEB["WEB EC2"]
            WAS["WAS EC2"]
        end
    end
    subgraph VPC3["CERT VPC 10.50.0.0/16"]
        subgraph Sub3["Private Subnet 10.50.10.0/24"]
            Wazuh["Wazuh EC2"]
            Velo["Velociraptor EC2"]
        end
    end 
VPC2 <-->|"VPC Peering"| VPC3
```
### Route Table
```mermaid
sequenceDiagram
    participant SUB3 as CERT Subnet 라우트 테이블<br/>(10.50.10.0/24)
    participant SUB2 as WEB/WAS Subnet 라우트 테이블<br/>(10.60.10.0/24)

    SUB2<<->>SUB3: Routing
```
### Security Group Ingress/Egress
```mermaid
flowchart LR
    subgraph VPC2["서비스 VPC 10.60.0.0/16"]
        subgraph Sub2["Public Subnet 10.60.10.0/24"]
            WEB["WEB EC2"]
            WAS["WAS EC2"]
            PHP["PHP EC2"]
            CI["CI EC2"]
        end
    end
    subgraph VPC3["CERT VPC 10.50.0.0/16"]
        subgraph Sub3["Private Subnet 10.50.10.0/24"]
            Wazuh["Wazuh EC2"]
            Velo["Velociraptor EC2"]
        end
    end 
Wazuh <-->|"TCP 1514/1515"| WEB
Wazuh <-->|"TCP 1514/1515"| WAS
Wazuh <-->|"TCP 1514/1515"| PHP
Wazuh <-->|"TCP 1514/1515"| CI
Velo <-->|"TCP 8000"| WEB
Velo <-->|"TCP 8000"| WAS
Velo <-->|"TCP 8000"| PHP
Velo <-->|"TCP 8000"| CI
```