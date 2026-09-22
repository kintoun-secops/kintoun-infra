# 문서 작성과 미리 보기

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

## 문서 CI와 배포

자동 빌드 흐름, HTML 아티팩트와 Pages 배포는 [문서 CI와 Pages](ci/docs.md)에 있다.
