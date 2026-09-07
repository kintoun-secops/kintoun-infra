# 문서 빌드와 Pages

문서는 `docs/`의 Markdown을 MkDocs와 Material 테마로 빌드한다.
탐색 구조는 `mkdocs.yml`, 직접 의존성 버전은 `requirements-docs.txt`에서 관리한다.

## 로컬 미리 보기

CI와 같은 Python 3.12를 사용한다. 저장소 루트에서 실행한다.

```bash
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-docs.txt
python -m mkdocs serve
```

`http://127.0.0.1:8000`에서 수정 내용을 확인한다. CI와 같은 검증은 다음 명령이다.

```bash
python -m mkdocs build --strict
```

HTML은 `site/`에 생성된다. `site/`와 `.venv/`는 Git에서 제외한다.
빌드 결과를 HTTP로 확인할 때는 `python -m http.server 8000 --directory site`를 실행한다.

## 작성 규칙

- 새 페이지는 `docs/` 아래에 만들고 `mkdocs.yml`의 `nav`에 등록한다.
- 문서끼리는 상대 Markdown 링크를 사용한다. 소스 코드는 저장소의 GitHub 링크로 연결한다.
- 코드 동작과 향후 계획을 구분하고, 루트의 입력·출력이나 CI를 바꾸면 관련 문서도 갱신한다.
- Mermaid 코드 블록으로 구조를 그릴 수 있다. 렌더링은 브라우저에서 이루어지므로 미리 보기로 확인한다.
- 비밀번호, 액세스 키, state, plan 원문은 문서와 예시에 넣지 않는다.
- 참고와 동작 설명은 `!!! note` 또는 `!!! info`로 표시한다. 주의가 필요한 작업은
  `!!! warning`, 데이터 삭제처럼 피해가 큰 작업은 `!!! danger`로 표시한다.
  상자 본문은 네 칸 들여 쓰며, 일반 설명을 경고로 강조하지 않는다.

```markdown
!!! note "참고"
    matrix는 같은 작업을 루트 목록의 각 항목에 대해 실행합니다.

!!! warning "교체 계획 확인"
    Wazuh EC2의 교체가 계획되면 병합 전에 원인을 확인합니다.
```

`???`는 참고 유형이 아니라 접어서 펼치는 문법이다. 현재 설정은 `!!!` 상자를 사용한다.

strict 빌드는 누락된 탐색 항목, 문서·이미지 링크, 존재하지 않는 앵커를 오류로 처리한다.
외부 URL의 HTTP 상태나 Mermaid 문법까지 검증하지는 않는다.
설정은 [MkDocs 공식 문서](https://www.mkdocs.org/user-guide/configuration/#validation)를 따른다.

## GitHub Actions CI

`.github/workflows/docs.yml`은 모든 PR, 문서 관련 경로가 바뀐 main push, 수동 실행에서 동작한다.

1. 첫 스텝이 PR의 변경 파일을 조회해 `docs/`, Markdown 파일, `mkdocs.yml`,
   `requirements-docs.txt`, 워크플로 자신 가운데 하나라도 바뀌었는지 확인한다.
   해당 없는 PR은 이후 스텝을 모두 건너뛴다. push와 수동 실행은 항상 빌드한다.
2. Python 3.12를 준비하고 러너 OS, Python 패치 버전, `requirements-docs.txt` 해시를
   키로 가상환경을 캐시한다. 캐시가 있으면 의존성 설치를 건너뛴다.
3. `.venv/bin/python -m mkdocs build --strict`로 문서와 내부 링크를 검증한다.
4. `site/`만 `docs-site` 아티팩트로 7일 보관한다.

PR 트리거에 경로 필터를 두지 않는 이유는 필수 검사 때문이다. 필터로 실행 자체가
건너뛰어진 워크플로는 검사 상태를 보고하지 않아 머지를 영원히 막는다. 반면 `if`로
건너뛴 스텝은 성공으로 보고되므로 문서와 무관한 PR도 몇 초 만에 통과한다.
main push는 필수 검사가 아니므로 트리거의 `paths` 목록으로 거른다. 이 목록과
감지 스텝의 목록은 항상 함께 고친다.

필요 권한은 `contents: read`와 변경 파일 조회용 `pull-requests: read`다.
AWS 자격증명과 Pages 권한은 필요하지 않다.
액션은 SHA로 고정하고 Dependabot이 액션과 pip 의존성을 매주 확인한다.
필수 검사로 사용할 이름은 **`docs / build`**다.

Actions → docs → 실행 결과 → Artifacts에서 `docs-site`를 받아 압축을 풀고
해당 디렉터리에서 `python -m http.server 8000`을 실행하면 빌드 결과를 볼 수 있다.
문서와 무관한 push는 빌드하지 않으므로 아티팩트는 마지막 문서 변경 실행에서 받는다.
Material의 Mermaid 렌더러는 외부 CDN을 사용하므로 다이어그램 표시는 인터넷 연결이 필요하다.

## 의존성 상태 점검

의존성 상태 감시는 Dependabot에 맡긴다. pip 설정은 이름에 `requirements`가
들어간 `.txt`를 수집하므로 `requirements-docs.txt`가 감시 대상이고, 새 버전이
나오면 minor·patch는 하나의 PR로 묶이며 major는 개별 PR로 온다.
알려진 취약점 알림은 저장소 Settings에서 Dependency graph와 Dependabot alerts를
켜서 받는다. 이 알림은 requirements에 적힌 직접 의존성이 대상이며 전이 의존성은
검사하지 않는다.

## MkDocs 2.0 대응

mkdocs는 1.6.1, mkdocs-material은 9.7.7로 고정하며 2026-09-07 확인 기준
두 버전 모두 최신 정식 릴리스다. MkDocs 2.0은 프리릴리스 상태이며 플러그인
시스템 제거, 테마 재작성, TOML 설정 전환으로 Material 테마와 호환되지 않고,
mkdocs-material이 `mkdocs<2`를 선언해 설치 자체가 차단된다.

2.x 정식 릴리스가 나오면 Dependabot이 major 개별 PR을 올린다.
그 PR은 병합하지 않는다 — 의존성 충돌로 CI 빌드도 실패한다.
이 신호로 충분하므로 Material이 빌드마다 출력하는 2.0 경고 배너는
CI에서 `NO_MKDOCS_2_WARNING=1`로 끈다.
1.x는 더 이상 릴리스가 없으므로, 그 시점에 Material 팀의 1.x 호환 후속 도구인
[Zensical](https://zensical.org/)의 안정화 여부를 평가해 이행을 결정한다.

## 현재 Pages 배포를 두지 않은 이유

2026-09-07 확인 기준 `kintoun-secops`는 GitHub Free 조직이고 이 저장소는 private다.
이 조합은 GitHub Pages를 지원하지 않으므로 현재 파이프라인은 CI와 아티팩트까지만 제공한다.

| GitHub 조직 구성 | Private 저장소에서 Pages 생성 | 사이트 접근 범위 |
| --- | --- | --- |
| GitHub Free | 불가 | 해당 없음 |
| GitHub Team | 가능 | 사이트는 공개 |
| GitHub Enterprise Cloud | 가능 | 조직 설정에 따라 비공개 게시 가능 |

저장소가 private인 것과 배포된 사이트가 private인 것은 별개다.
지원 플랜은 [GitHub Pages 안내](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages),
접근 제어는 [사이트 가시성 안내](https://docs.github.com/en/enterprise-cloud%40latest/pages/getting-started-with-github-pages/changing-the-visibility-of-your-github-pages-site)를 확인한다.

## Pages를 사용할 수 있게 된 뒤

1. 플랜과 문서 공개 범위를 결정한 뒤 저장소 Settings → Pages의 Source를 GitHub Actions로 설정한다.
2. 제공된 실제 사이트 URL을 `mkdocs.yml`의 `site_url`에 추가한다.
3. 빌드 결과를 `actions/upload-pages-artifact`로 올리고, build 성공에 의존하는
   `deploy` job에서 `actions/deploy-pages`를 실행하도록 워크플로를 확장한다. 액션은 SHA로 고정한다.
4. deploy job은 main의 push 또는 main에서 실행한 workflow_dispatch로 제한하고
   `github-pages` environment, `pages: write`, `id-token: write`를 설정한다.
5. PR에서는 기존 빌드 검증만 실행하며 배포하지 않는다.

구현 시 [GitHub의 사용자 지정 Pages 워크플로 안내](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)를 기준으로 확인한다.
