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

strict 빌드는 누락된 탐색 항목, 문서·이미지 링크, 존재하지 않는 앵커를 오류로 처리한다.
외부 URL의 HTTP 상태나 Mermaid 문법까지 검증하지는 않는다.
설정은 [MkDocs 공식 문서](https://www.mkdocs.org/user-guide/configuration/#validation)를 따른다.

## GitHub Actions CI

`.github/workflows/docs.yml`은 모든 PR, main push, 수동 실행에서 동작한다.
경로 필터가 없어서 문서를 필수 검사로 지정해도 건너뛴 실행 때문에 대기하지 않는다.

1. Python 3.12와 고정한 문서 의존성을 준비한다.
2. `python -m mkdocs build --strict`로 문서와 내부 링크를 검증한다.
3. `site/`만 `docs-site` 아티팩트로 7일 보관한다.

필요 권한은 `contents: read`뿐이다. AWS 자격증명과 Pages 권한은 필요하지 않다.
액션은 SHA로 고정하고 Dependabot이 액션과 pip 의존성을 매주 확인한다.
필수 검사로 사용할 이름은 **`docs / build`**다.

Actions → docs → 실행 결과 → Artifacts에서 `docs-site`를 받아 압축을 풀고
해당 디렉터리에서 `python -m http.server 8000`을 실행하면 빌드 결과를 볼 수 있다.
Material의 Mermaid 렌더러는 외부 CDN을 사용하므로 다이어그램 표시는 인터넷 연결이 필요하다.

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
