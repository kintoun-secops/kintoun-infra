# 차단형 가드레일 — 이 패키지의 deny 는 plan 잡을 실패시킨다 (자문형인 iam.rego 와 다르다).
# 경계 정책이 apply 시점에 거부할 위반을 plan 시점으로 앞당길 뿐이므로 차단이 정당하다.
package terraform.guardrail

import data.terraform.iam
import rego.v1

role_path_prefix := "/project/"

deny contains iam.finding("high", sprintf("[차단] 권한 경계 없는 롤 생성: `%s`", [rc.address]), "인프라 롤에는 권한 경계를 붙여야 합니다. 경계 정책이 apply 단계에서 거부합니다.") if {
	some rc in iam.changes
	rc.type == "aws_iam_role"
	iam.acted(rc, "create")
	not iam.boundary(rc, "after")
}

deny contains iam.finding("high", sprintf("[차단] 프로젝트 경로 밖의 롤 생성: `%s` (path=%v)", [rc.address, object.get(rc.change.after, "path", "(없음)")]), sprintf("인프라 롤은 `%s` 하위에 만들어야 합니다. 경계 정책이 apply 단계에서 거부합니다.", [role_path_prefix])) if {
	some rc in iam.changes
	rc.type == "aws_iam_role"
	iam.acted(rc, "create")
	not compliant_path(rc)
}

# `not startswith(없는키, ...)` 는 발화하지 않는다 — 부재·null 도 위반으로 치려면
# "준수임이 증명될 때만 통과" 형태로 뒤집어야 한다 (fail-closed).
compliant_path(rc) if {
	p := rc.change.after.path
	is_string(p)
	startswith(p, role_path_prefix)
}
