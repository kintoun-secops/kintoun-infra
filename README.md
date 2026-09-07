# kintoun-infra

근두운 AWS 보안 실습 환경의 Terraform 저장소다. Wazuh 서버, 공유 네트워크,
서비스 IAM과 팀원 IAM을 관리하며 GitHub Actions가 PR plan과 main apply를 수행한다.

기술 문서는 [프로젝트 개요](docs/index.md)에서 시작한다.
인프라 초기 설정은 [Bootstrap](docs/modules/bootstrap.md),
개발 절차는 [개발 규칙](docs/conventions.md)을 참고한다.

## 문서 미리 보기

```bash
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-docs.txt
python -m mkdocs serve
```

CI와 같은 검증은 `python -m mkdocs build --strict`로 실행한다.
문서 CI와 Pages 전환 조건은 [문서 빌드와 Pages](docs/documentation.md)에 있다.
