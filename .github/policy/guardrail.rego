package terraform.guardrail

import data.terraform.iam
import rego.v1

role_path_prefix := "/project/"

deny contains iam.format_finding if not iam.format_supported

created_roles contains rc if {
	some rc in iam.changes
	rc.type == "aws_iam_role"
	iam.acted(rc, "create")
}

deny contains iam.finding_at("high", sprintf("[차단] 권한 경계 없는 롤 생성: `%s`", [rc.address]), "권한 경계가 없는 롤 생성은 경계 정책이 apply 단계에서 거부합니다.", rc) if {
	some rc in created_roles
	not iam.unknown_after_field(rc, "permissions_boundary")
	not iam.boundary(rc, "after")
}

deny contains iam.finding_at("high", sprintf("[차단] 권한 경계 미확정 롤 생성: `%s`", [rc.address]), "경계 ARN 이 plan 시점에 확정되지 않아 경계 정책의 조건을 만족하는지 확인할 수 없습니다.", rc) if {
	some rc in created_roles
	iam.unknown_after_field(rc, "permissions_boundary")
}

deny contains iam.finding_at("high", sprintf("[차단] 프로젝트 경로 밖의 롤 생성: `%s` (path=%s)", [rc.address, shown_path(rc)]), sprintf("`%s` 밖의 롤 생성은 경계 정책이 apply 단계에서 거부합니다.", [role_path_prefix]), rc) if {
	some rc in created_roles
	not compliant_path(rc)
}

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
