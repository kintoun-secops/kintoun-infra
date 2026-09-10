# terraform plan JSON 에 대한 IAM 정책. `conftest test plan.json -p .github/policy`
# 규칙은 AWS 리소스 타입과 plan 액션에만 건다 — 변수명·파일 구조를 파싱하지 않는다.
# 차단하지 않는다. deny 는 리뷰어에게 보이는 신호이고 판단은 사람이 한다.
package terraform.iam

import rego.v1

critical_policy := `:policy/(.*Administrator|.*PowerUser|IAMFullAccess)`

broad_policy := `:policy/.*FullAccess`

attachment_types := {
	"aws_iam_user_policy_attachment",
	"aws_iam_group_policy_attachment",
	"aws_iam_role_policy_attachment",
	"aws_iam_policy_attachment",
}

policy_fields := {
	"aws_iam_policy": "policy",
	"aws_iam_user_policy": "policy",
	"aws_iam_group_policy": "policy",
	"aws_iam_role_policy": "policy",
	"aws_iam_role": "assume_role_policy",
}

# ---- 공통 ---------------------------------------------------------------

finding(level, text, why) := {"level": level, "msg": text, "why": why}

# 리소스 주소는 라인 코멘트가 소스 위치를 찾는 데 쓴다. 메시지 문자열에서 다시 파싱하지 않는다.
finding_at(level, text, why, rc) := object.union(finding(level, text, why), {"address": rc.address})

# import 는 no-op 으로도 나타나므로 걸러내지 않는다.
changes contains rc if {
	some rc in input.resource_changes
	startswith(rc.type, "aws_iam_")
	not only_noise(rc)
}

only_noise(rc) if {
	not rc.change.importing
	every a in rc.change.actions {
		a in {"no-op", "read"}
	}
}

acted(rc, a) if a in rc.change.actions

is_replace(rc) if {
	acted(rc, "delete")
	acted(rc, "create")
}

# null 은 정의된 값이라 `not` 에 안 걸린다 — 문자열일 때만 정의되게 눕힌다.
boundary(rc, which) := b if {
	b := rc.change[which].permissions_boundary
	is_string(b)
}

# 모르는 메이저 버전이면 규칙이 조용히 빗나가는 대신 여기서 멈춘다 (공식 문서 지시).
deny contains finding("high", "plan JSON 형식 버전을 해석할 수 없습니다", sprintf("format_version=%v: 이 정책은 1.x 만 해석합니다. 갱신 전까지 검사 결과를 신뢰하지 마십시오.", [object.get(input, "format_version", "(없음)")])) if {
	not startswith(object.get(input, "format_version", ""), "1.")
}

# ---- 파괴적 변경 --------------------------------------------------------

deny contains finding_at("high", sprintf("사용자 삭제: `%s`", [rc.address]), "되돌려도 비밀번호·액세스 키·MFA 디바이스는 복원되지 않습니다.", rc) if {
	some rc in changes
	rc.type == "aws_iam_user"
	acted(rc, "delete")
	not is_replace(rc)
}

deny contains finding_at("high", sprintf("IAM 개체 삭제: `%s`", [rc.address]), "이 개체로 부여하던 권한이나 제약이 사라집니다. MFA·경계 관련이면 보안 완화입니다.", rc) if {
	some rc in changes
	rc.type != "aws_iam_user"
	acted(rc, "delete")
	not is_replace(rc)
}

deny contains finding_at("high", sprintf("IAM 개체 재생성%s: `%s`", [import_tag(rc), rc.address]), "제자리 수정이 아니라 삭제 후 재생성입니다. import 중이라면 코드가 실제 자원과 달라 운영 중인 자원을 지우는 계획입니다.", rc) if {
	some rc in changes
	is_replace(rc)
}

import_tag(rc) := " [import]" if rc.change.importing

import_tag(rc) := "" if not rc.change.importing

# ---- 권한 경계 ----------------------------------------------------------

deny contains finding_at("high", sprintf("권한 경계 없는 사용자 생성: `%s`", [rc.address]), "사용자에게 부여되는 권한을 제한할 경계가 없습니다.", rc) if {
	some rc in changes
	rc.type == "aws_iam_user"
	acted(rc, "create")
	not boundary(rc, "after")
}

# 경계는 제자리 갱신 대상이라 create 만 보면 변수를 비우는 조용한 update 를 놓친다.
deny contains finding_at("high", boundary_text(rc), "기존 경계가 제한하던 권한이 유효해질 수 있습니다. 교체한 경계의 허용 범위를 확인하십시오.", rc) if {
	some rc in changes
	rc.type in {"aws_iam_user", "aws_iam_role"}
	acted(rc, "update")
	not unknown_after_field(rc, "permissions_boundary")
	boundary_changed(rc)
}

# 미확정 값은 after 에서 빠진다. 실제 제거와 구분해 검토 대상으로 남긴다.
warn contains finding_at("warn", sprintf("권한 경계 미확정: `%s`", [rc.address]), "적용 후 경계를 plan에서 확인할 수 없습니다. 기존 경계와 적용될 경계의 허용 범위를 확인하십시오.", rc) if {
	some rc in changes
	rc.type in {"aws_iam_user", "aws_iam_role"}
	acted(rc, "update")
	unknown_after_field(rc, "permissions_boundary")
}

unknown_after_field(rc, field) if rc.change.after_unknown == true

unknown_after_field(rc, field) if rc.change.after_unknown[field] == true

boundary_changed(rc) if {
	boundary(rc, "before")
	not boundary(rc, "after")
}

boundary_changed(rc) if boundary(rc, "before") != boundary(rc, "after")

boundary_text(rc) := sprintf("권한 경계 교체 (`%s` → `%s`): `%s`", [boundary(rc, "before"), boundary(rc, "after"), rc.address]) if boundary(rc, "after")

boundary_text(rc) := sprintf("권한 경계 제거: `%s`", [rc.address]) if not boundary(rc, "after")

# ---- 권한 부여 ----------------------------------------------------------

deny contains finding_at("high", sprintf("특권 정책 연결: `%s` → `%s`", [rc.change.after.policy_arn, rc.address]), "관리자·IAM 전체 권한입니다. 이 연결이 의도된 것인지 본문에 사유를 남기십시오.", rc) if {
	some rc in changes
	rc.type in attachment_types
	attachment_grants(rc)
	regex.match(critical_policy, rc.change.after.policy_arn)
}

warn contains finding_at("warn", sprintf("광범위한 정책 연결: `%s` → `%s`", [rc.change.after.policy_arn, rc.address]), "해당 서비스 전체 권한입니다. 더 좁은 정책으로 대체할 수 있는지 확인하십시오.", rc) if {
	some rc in changes
	rc.type in attachment_types
	attachment_grants(rc)
	not regex.match(critical_policy, rc.change.after.policy_arn)
	regex.match(broad_policy, rc.change.after.policy_arn)
}

# 일괄 연결 리소스는 users·groups·roles 추가가 update 이다. 연결 제거만 있는 갱신은 제외한다.
attachment_grants(rc) if acted(rc, "create")

attachment_grants(rc) if rc.change.importing

attachment_grants(rc) if {
	acted(rc, "update")
	rc.change.before.policy_arn != rc.change.after.policy_arn
}

attachment_grants(rc) if {
	acted(rc, "update")
	rc.type == "aws_iam_policy_attachment"
	some kind in {"users", "groups", "roles"}
	some principal in object.get(rc.change.after, kind, [])
	not principal in object.get(rc.change.before, kind, [])
}

deny contains finding_at("high", sprintf("모든 작업을 허용하는 정책: `%s`", [rc.address]), "`Action: \"*\"` 와 `Resource: \"*\"` 를 동시에 허용합니다.", rc) if {
	some rc in changes
	is_object(rc.change.after)
	star_policy(rc.change.after.policy)
}

warn contains finding_at("warn", sprintf("정책 본문 미검사: `%s.%s`", [rc.address, field]), "본문이 미확정이거나 JSON 정책 문장으로 읽히지 않습니다. 확정된 본문과 Access Analyzer 결과를 확인하십시오.", rc) if {
	some rc in changes
	is_object(rc.change.after)
	field := policy_fields[rc.type]
	not readable_policy(object.get(rc.change.after, field, null))
}

# JSON 해석과 문장 형태만 확인한다. 정책 문법과 유효 권한은 별도 검사 대상이다.
readable_policy(doc) if {
	is_string(doc)
	parsed := json.unmarshal(doc)
	is_object(parsed)
	every statement in as_array(parsed.Statement) {
		is_object(statement)
	}
}

star_policy(doc) if {
	parsed := json.unmarshal(doc)
	some s in as_array(parsed.Statement)
	s.Effect == "Allow"
	"*" in as_array(s.Action)
	"*" in as_array(s.Resource)
}

as_array(x) := x if is_array(x)

as_array(x) := [x] if not is_array(x)

# ---- 정보 ---------------------------------------------------------------

warn contains finding_at("warn", sprintf("그룹 소속 변경: `%s` → %s", [rc.address, concat(", ", as_array(rc.change.after.groups))]), "그룹을 통해 부여되는 권한이 바뀝니다.", rc) if {
	some rc in changes
	rc.type == "aws_iam_user_group_membership"
	not acted(rc, "delete")
}

warn contains finding_at("warn", sprintf("사용자 생성: `%s`", [rc.address]), "적용 후 콘솔 액세스 활성화와 MFA 등록이 필요합니다.", rc) if {
	some rc in changes
	rc.type == "aws_iam_user"
	acted(rc, "create")
	not is_replace(rc)
}

warn contains finding_at("warn", sprintf("그룹 생성: `%s`", [rc.address]), "새 권한 부여 지점입니다. 연결되는 정책과 소속 인원을 함께 확인하십시오.", rc) if {
	some rc in changes
	rc.type == "aws_iam_group"
	acted(rc, "create")
}

warn contains finding_at("warn", sprintf("코드로 들여옴 (import): `%s`", [rc.address]), "id 가 의도한 실제 자원인지 확인하십시오. 잘못된 id 는 다른 자원을 이 주소에 묶습니다.", rc) if {
	some rc in changes
	rc.change.importing
	not is_replace(rc)
}
