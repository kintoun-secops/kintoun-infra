<!--
제목 규칙: <type>(<scope>): <요약>
  type  : feat | fix | refactor | chore | docs | ci | revert
  scope : bootstrap | platform | platform/iam | identity | modules/<이름> | .github
  예) feat(platform/iam): Wazuh 인스턴스 롤에 권한 경계 부착
브랜치: feat/... fix/... chore/... (소문자·하이픈, 언더스코어 금지)
머지  : squash merge — 커밋 하나 = 인프라 변경 하나
-->

## 변경 요약

<!-- 무엇을 왜 바꾸는지 2~3줄 -->

## terraform plan 결과

<!-- CI plan 코멘트로 갈음 가능. 요약만 적으면 추가 n / 변경 n / 삭제 n -->

## 체크리스트

- [ ] PR 제목이 `<type>(<scope>): <요약>` 형식이다
- [ ] plan 에 의도하지 않은 변경 없음 (특히 replace / destroy)
- [ ] IAM 개체를 새로 만들면 권한 경계를 붙였다
- [ ] 삭제(destroy)가 포함되면 본문에 사유를 적었다
- [ ] 비밀값을 코드·tfvars·plan 출력에 노출하지 않았다
- [ ] `.terraform.lock.hcl` 변경이 있으면 함께 커밋했다
