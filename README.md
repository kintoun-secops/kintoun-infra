# kintoun-infra

근두운 AWS 보안 실습 환경의 Terraform 저장소다. Wazuh 서버, 공유 네트워크,
서비스 IAM과 팀원 IAM을 관리하며 GitHub Actions가 PR plan과 main apply를 수행한다.

기술 문서는 [프로젝트 개요](docs/index.md)에서 시작한다.
인프라 초기 설정은 [Bootstrap](docs/modules/bootstrap.md),
개발 절차는 [개발 규칙](docs/conventions.md),
자동 검사·적용과 Rego 정책은 [CI 문서](docs/ci/index.md)를 참고한다.

## 코드 포맷

Terraform은 `terraform fmt`, JavaScript와 JSON은 Prettier로 정리하며 npm 스크립트 하나가 둘을 함께 실행한다.
실행에는 다음 세 가지가 필요하다. AWS 자격증명은 필요하지 않다.

| 요건 | 값 |
| --- | --- |
| Node.js | `.nvmrc`의 22 이상. nvm을 쓰면 `nvm install` 후 `nvm use` |
| npm | Node.js에 포함된 버전. `npm ci`로 Prettier를 설치한다 |
| Terraform | 1.11 이상, PATH에 있어야 한다 |

```bash
npm ci --ignore-scripts
npm run format
npm run format:check
```

`format`은 자동 수정, `format:check`는 CI와 같은 검사다.
PR CI가 같은 명령을 실행하므로 포맷이 어긋나면 필수 검사가 실패하고 머지할 수 없다.
검사 대상과 규칙, 실패 처리와 편집기 연동은 [포맷 검사](docs/ci/format.md)를 참고한다.

## 문서 미리 보기

```bash
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-docs.txt
python -m mkdocs serve
```

CI와 같은 검증은 `python -m mkdocs build --strict`로 실행한다.
작성 규칙은 [문서 작성과 미리 보기](docs/documentation.md),
문서 CI와 Pages 배포는 [문서 CI와 Pages](docs/ci/docs.md)에 있다.
