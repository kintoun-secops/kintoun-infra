# Kintoun Infra

근두운 보안 실습 환경을 AWS에 구성하고 Terraform으로 관리하는 저장소다.
현재 코드는 Wazuh All-in-one 서버, 네트워크, 서비스 IAM, 팀원 IAM과
GitHub Actions의 plan/apply 자동화를 포함한다.

## 문서 읽는 순서

| 목적 | 시작점 |
| --- | --- |
| 전체 구성과 모듈 경계 이해 | [아키텍처](architecture.md) |
| 원격 state와 CI 자격증명 준비 | [Bootstrap](modules/bootstrap.md) |
| Wazuh 인프라 변경 | [Platform](modules/platform.md) |
| 팀원 온보딩과 권한 변경 | [Identity](modules/identity.md), [팀원 추가](runbooks/add-user.md) |
| 새 Terraform 루트 추가와 루트 매니페스트 작성 | [저장소 구조](structure.md) |
| 루트 모듈 파일 규칙과 Git 컨벤션 | [개발 규칙](conventions.md) |
| PR 검사와 main 적용 흐름 확인 | [Terraform CI](ci.md) |
| 기술 문서 수정과 빌드 | [문서 빌드와 Pages](documentation.md) |

## 저장소 구성

`bootstrap`, `platform/network`, `platform/wazuh`, `identity`가 각각 state 하나와 apply 단위 하나를 가진다.
`bootstrap`은 운영자가 직접 적용하고 나머지는 CI가 적용한다.
기존 `platform`은 사용자 정책을 유지하고 network와 wazuh의 이전 대상만 관리 해제한다.
실제 CI 대상과 순서는 루트 매니페스트 `.github/terraform-roots.json`이 결정한다.
전체 디렉터리 구성, 루트 추가 절차, 매니페스트 형식은 [저장소 구조](structure.md)에 있다.

## 구현 범위

문서는 저장소에 있는 코드의 동작을 설명한다. 실제 AWS 배포 상태는
`terraform plan`과 운영 환경에서 확인한다.

현재 `main` 기반 코드에는 Wazuh와 공유할 VPC·IAM·보안 그룹 출력이 있지만,
별도의 victim, attacker, logging 루트와 Wazuh 데이터 전용 EBS는 아직 없다.
후속 루트는 [루트 간 참조 규칙](conventions.md#루트-사이의-참조)에 따라 추가한다.
