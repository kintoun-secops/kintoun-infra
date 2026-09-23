# 차단형 가드레일 — 이 패키지의 deny 는 plan 잡을 실패시킨다 (자문형인 iam.rego 와 다르다).
# 경계 정책이 apply 시점에 거부할 위반을 plan 시점으로 앞당길 뿐이므로 차단이 정당하다.
package terraform.guardrail

import data.terraform.iam
import rego.v1

role_path_prefix := "/project/"

# 형식을 못 읽으면 아래 규칙이 조용히 빗나간다. 자문이 아니라 여기서 멈춘다.
deny contains iam.format_finding if not iam.format_supported

created_roles contains rc if {
	some rc in iam.changes
	rc.type == "aws_iam_role"
	iam.acted(rc, "create")
}

deny contains iam.finding_at("high", sprintf("[차단] 권한 경계 없는 롤 생성: `%s`", [rc.address]), "인프라 롤에는 권한 경계를 붙여야 합니다. 경계 정책이 apply 단계에서 거부합니다.", rc) if {
	some rc in created_roles
	not iam.unknown_after_field(rc, "permissions_boundary")
	not iam.boundary(rc, "after")
}

# 미확정 경계는 준수를 증명하지 못한다. 자문 패키지처럼 확인 항목으로 낮추지 않고 막는다 (fail-closed).
deny contains iam.finding_at("high", sprintf("[차단] 권한 경계 미확정 롤 생성: `%s`", [rc.address]), "경계 ARN 이 plan 시점에 확정되지 않아 준수를 확인할 수 없습니다. 확정된 경계 ARN 을 지정하십시오.", rc) if {
	some rc in created_roles
	iam.unknown_after_field(rc, "permissions_boundary")
}

deny contains iam.finding_at("high", sprintf("[차단] 프로젝트 경로 밖의 롤 생성: `%s` (path=%s)", [rc.address, shown_path(rc)]), sprintf("인프라 롤은 `%s` 하위에 만들어야 합니다. 경계 정책이 apply 단계에서 거부합니다.", [role_path_prefix]), rc) if {
	some rc in created_roles
	not compliant_path(rc)
}

# `not startswith(없는키, ...)` 는 발화하지 않는다 — 부재·null·미확정도 위반으로 치려면
# "준수임이 증명될 때만 통과" 형태로 뒤집어야 한다 (fail-closed).
compliant_path(rc) if {
	p := rc.change.after.path
	is_string(p)
	startswith(p, role_path_prefix)
}

shown_path(rc) := p if {
	p := rc.change.after.path
	is_string(p)
}

shown_path(rc) := "(미확정)" if {
	not is_string(object.get(rc.change.after, "path", null))
	iam.unknown_after_field(rc, "path")
}

shown_path(rc) := "(없음)" if {
	not is_string(object.get(rc.change.after, "path", null))
	not iam.unknown_after_field(rc, "path")
}
