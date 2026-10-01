package terraform.iam

import rego.v1

critical_policy := `:policy/(.*Administrator|.*PowerUser|IAMFullAccess)`

broad_policy := `:policy/.*FullAccess`

boundary_types := {"aws_iam_user", "aws_iam_role"}

attachment_types := {
	"aws_iam_user_policy_attachment",
	"aws_iam_group_policy_attachment",
	"aws_iam_role_policy_attachment",
	"aws_iam_policy_attachment",
}

exclusive_attachment_types := {
	"aws_iam_user_policy_attachments_exclusive",
	"aws_iam_group_policy_attachments_exclusive",
	"aws_iam_role_policy_attachments_exclusive",
}

attachment_resources := attachment_types | exclusive_attachment_types

arn_field(rc) := "policy_arn" if rc.type in attachment_types

arn_field(rc) := "policy_arns" if rc.type in exclusive_attachment_types

arn_field(rc) := "managed_policy_arns" if rc.type == "aws_iam_role"

policy_fields := {
	"aws_iam_policy": "policy",
	"aws_iam_user_policy": "policy",
	"aws_iam_group_policy": "policy",
	"aws_iam_role_policy": "policy",
	"aws_iam_role": "assume_role_policy",
}

finding(level, text, why) := {"level": level, "msg": text, "why": why}

finding_at(level, text, why, rc) := object.union(finding(level, text, why), {"address": rc.address})

changes contains rc if {
	some rc in input.resource_changes
	startswith(rc.type, "aws_iam_")
	not only_noise(rc)
}

live contains rc if {
	some rc in changes
	is_object(rc.change.after)
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

mutates(rc) if acted(rc, "create")

mutates(rc) if acted(rc, "update")

boundary(rc, which) := b if {
	b := rc.change[which].permissions_boundary
	is_string(b)
	b != ""
}

unknown_after_field(rc, field) if rc.change.after_unknown == true

unknown_after_field(rc, field) if walk(rc.change.after_unknown[field], [_, true])

format_supported if startswith(object.get(input, "format_version", ""), "1.")

format_finding := finding("high", "plan JSON 형식 버전을 해석할 수 없습니다", sprintf("format_version 이 %v 입니다. 이 정책은 1.x 형식만 읽으므로 다른 규칙의 결과가 정확하지 않을 수 있습니다.", [object.get(input, "format_version", "(없음)")]))

deny contains finding_at("high", sprintf("사용자 삭제: `%s`", [rc.address]), "되돌려도 비밀번호, 액세스 키, MFA 디바이스는 복원되지 않습니다.", rc) if {
	some rc in changes
	rc.type == "aws_iam_user"
	acted(rc, "delete")
	not is_replace(rc)
}

deny contains finding_at("high", sprintf("IAM 개체 삭제: `%s`", [rc.address]), "이 개체로 부여하던 권한이나 제약이 사라집니다. MFA 나 권한 경계에 관련된 개체이면 그 제약이 풀립니다.", rc) if {
	some rc in changes
	rc.type != "aws_iam_user"
	acted(rc, "delete")
	not is_replace(rc)
}

deny contains finding_at("high", sprintf("IAM 개체 재생성%s: `%s`", [import_tag(rc), rc.address]), "삭제 후 다시 만드는 계획입니다. import 중이면 코드와 실제 자원이 달라 운영 중인 자원을 지웁니다.", rc) if {
	some rc in changes
	is_replace(rc)
}

import_tag(rc) := " [import]" if rc.change.importing

import_tag(rc) := "" if not rc.change.importing

deny contains finding_at("high", sprintf("권한 경계 없는 사용자 생성: `%s`", [rc.address]), "사용자에게 부여되는 권한을 제한할 경계가 없습니다.", rc) if {
	some rc in changes
	rc.type == "aws_iam_user"
	acted(rc, "create")
	not unknown_after_field(rc, "permissions_boundary")
	not boundary(rc, "after")
}

deny contains finding_at("high", boundary_text(rc), "기존 경계가 제한하던 권한이 유효해질 수 있습니다.", rc) if {
	some rc in changes
	rc.type in boundary_types
	acted(rc, "update")
	not unknown_after_field(rc, "permissions_boundary")
	boundary_changed(rc)
}

boundary_watched(rc) if {
	rc.type == "aws_iam_user"
	acted(rc, "create")
}

boundary_watched(rc) if {
	rc.type in boundary_types
	acted(rc, "update")
}

warn contains finding_at("warn", sprintf("권한 경계 미확정: `%s`", [rc.address]), "적용될 경계를 plan 에서 확인할 수 없습니다.", rc) if {
	some rc in changes
	boundary_watched(rc)
	unknown_after_field(rc, "permissions_boundary")
}

boundary_changed(rc) if {
	boundary(rc, "before")
	not boundary(rc, "after")
}

boundary_changed(rc) if boundary(rc, "before") != boundary(rc, "after")

boundary_text(rc) := sprintf("권한 경계 교체: `%s` (`%s` 에서 `%s` 로)", [rc.address, boundary(rc, "before"), boundary(rc, "after")]) if boundary(rc, "after")

boundary_text(rc) := sprintf("권한 경계 제거: `%s`", [rc.address]) if not boundary(rc, "after")

arns_in(rc, which) := {arn |
	some arn in as_array(rc.change[which][arn_field(rc)])
	is_string(arn)
}

grants contains {"rc": rc, "arn": arn} if {
	some rc in live
	acted(rc, "create")
	some arn in arns_in(rc, "after")
}

grants contains {"rc": rc, "arn": arn} if {
	some rc in live
	rc.change.importing
	some arn in arns_in(rc, "after")
}

grants contains {"rc": rc, "arn": arn} if {
	some rc in live
	acted(rc, "update")
	some arn in arns_in(rc, "after")
	not arn in arns_in(rc, "before")
}

grants contains {"rc": rc, "arn": arn} if {
	some rc in live
	acted(rc, "update")
	rc.type == "aws_iam_policy_attachment"
	some arn in arns_in(rc, "after")
	some kind in {"users", "groups", "roles"}
	some principal in object.get(rc.change.after, kind, [])
	not principal in object.get(rc.change.before, kind, [])
}

deny contains finding_at("high", sprintf("특권 정책 연결: `%s` 에 `%s`", [g.rc.address, g.arn]), "관리자 권한이나 IAM 전체 권한을 부여합니다.", g.rc) if {
	some g in grants
	regex.match(critical_policy, g.arn)
}

warn contains finding_at("warn", sprintf("광범위한 정책 연결: `%s` 에 `%s`", [g.rc.address, g.arn]), "해당 서비스의 전체 권한을 부여합니다.", g.rc) if {
	some g in grants
	not regex.match(critical_policy, g.arn)
	regex.match(broad_policy, g.arn)
}

warn contains finding_at("warn", sprintf("정책 연결 미확정: `%s`", [rc.address]), "연결할 정책 ARN 이 plan 시점에 확정되지 않아 특권 정책과 광범위한 정책 검사를 하지 못했습니다.", rc) if {
	some rc in live
	rc.type in attachment_resources
	unknown_after_field(rc, arn_field(rc))
}

policy_slots contains {"rc": rc, "field": field, "doc": object.get(rc.change.after, field, null)} if {
	some rc in live
	field := policy_fields[rc.type]
}

policy_slots contains {"rc": rc, "field": sprintf("inline_policy[%d].policy", [i]), "doc": object.get(block, "policy", null)} if {
	some rc in live
	rc.type == "aws_iam_role"
	some i, block in rc.change.after.inline_policy
	is_object(block)
}

deny contains finding_at("high", sprintf("모든 작업을 허용하는 정책: `%s.%s`", [slot.rc.address, slot.field]), "`Action: \"*\"` 와 `Resource: \"*\"` 를 동시에 허용합니다.", slot.rc) if {
	some slot in policy_slots
	star_policy(slot.doc)
}

warn contains finding_at("warn", sprintf("정책 본문 미검사: `%s.%s`", [slot.rc.address, slot.field]), "본문이 미확정이거나 JSON 정책 문장으로 읽히지 않습니다. 확정된 본문은 Access Analyzer 단계에서 검사합니다.", slot.rc) if {
	some slot in policy_slots
	not readable_policy(slot.doc)
}

readable_policy(doc) if {
	is_string(doc)
	parsed := json.unmarshal(doc)
	is_object(parsed)
	every statement in as_array(parsed.Statement) {
		is_object(statement)
	}
}

star_policy(doc) if {
	is_string(doc)
	parsed := json.unmarshal(doc)
	some s in as_array(parsed.Statement)
	s.Effect == "Allow"
	"*" in as_array(s.Action)
	"*" in as_array(s.Resource)
}

as_array(x) := x if is_array(x)

as_array(x) := [x] if not is_array(x)

warn contains finding_at("warn", sprintf("그룹 소속 변경: `%s` (groups=%s)", [rc.address, groups_text(rc)]), "그룹을 통해 부여되는 권한이 바뀝니다.", rc) if {
	some rc in live
	rc.type == "aws_iam_user_group_membership"
	mutates(rc)
}

groups_text(rc) := "(미확정)" if unknown_after_field(rc, "groups")

groups_text(rc) := concat(", ", groups) if {
	not unknown_after_field(rc, "groups")
	groups := rc.change.after.groups
	is_array(groups)
}

groups_text(rc) := "(없음)" if {
	not unknown_after_field(rc, "groups")
	not is_array(rc.change.after.groups)
}

warn contains finding_at("warn", sprintf("사용자 생성: `%s`", [rc.address]), "적용 후 콘솔 액세스 활성화와 MFA 등록이 필요합니다.", rc) if {
	some rc in changes
	rc.type == "aws_iam_user"
	acted(rc, "create")
	not is_replace(rc)
}

warn contains finding_at("warn", sprintf("그룹 생성: `%s`", [rc.address]), "이 그룹에 연결되는 정책이 소속 사용자 전원에게 부여됩니다.", rc) if {
	some rc in changes
	rc.type == "aws_iam_group"
	acted(rc, "create")
}

warn contains finding_at("warn", sprintf("코드로 들여옴 (import): `%s`", [rc.address]), "id 가 가리키는 실제 자원이 이 주소에 묶입니다. id 가 다른 자원을 가리키면 그 자원을 코드가 관리하게 됩니다.", rc) if {
	some rc in changes
	rc.change.importing
	not is_replace(rc)
}
