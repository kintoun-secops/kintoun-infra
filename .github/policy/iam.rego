# terraform plan JSON 에 대한 IAM 정책. `conftest test plan.json -p .github/policy --all-namespaces`
# 규칙은 AWS 리소스 타입과 plan 액션에만 건다 — 변수명·파일 구조를 파싱하지 않는다.
# 차단하지 않는다. deny 는 리뷰어에게 보이는 신호이고 판단은 사람이 한다.
package terraform.iam

import rego.v1

critical_policy := `:policy/(.*Administrator|.*PowerUser|IAMFullAccess)`

broad_policy := `:policy/.*FullAccess`

boundary_types := {"aws_iam_user", "aws_iam_role"}

# 관리형 정책 ARN 이 적히는 자리는 타입마다 다르다. 부여 규칙은 arn_field 만 본다 — 자리가 늘면 여기에 추가한다.
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

# 역할의 managed_policy_arns 는 deprecated 지만 provider 6.x 에 남아 있다.
arn_field(rc) := "managed_policy_arns" if rc.type == "aws_iam_role"

# 정책 본문이 담기는 자리도 타입마다 다르다. 본문 규칙은 policy_slots 만 본다.
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

# 적용 후 상태가 있는 변경. 삭제만 있으면 after 가 null 이라 빠진다.
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

# 실제 자원이 바뀌는 변경. import 만 있는 no-op 은 아니다.
mutates(rc) if acted(rc, "create")

mutates(rc) if acted(rc, "update")

# null 은 정의된 값이라 `not` 에 안 걸리고, 빈 문자열은 is_string 을 통과한다 — 비어 있지 않은 문자열일 때만 정의되게 눕힌다.
boundary(rc, which) := b if {
	b := rc.change[which].permissions_boundary
	is_string(b)
	b != ""
}

# 미확정 값은 after 에서 빠지고 after_unknown 에 true 로 온다. 전체(true)·필드(true)·목록 원소([false, true]) 단위다.
unknown_after_field(rc, field) if rc.change.after_unknown == true

unknown_after_field(rc, field) if walk(rc.change.after_unknown[field], [_, true])

# 모르는 메이저 버전이면 규칙이 조용히 빗나간다 (공식 문서 지시). 차단은 guardrail, KMS 자문은 kms 가 이 판정을 쓴다.
format_supported if startswith(object.get(input, "format_version", ""), "1.")

format_finding := finding("high", "plan JSON 형식 버전을 해석할 수 없습니다", sprintf("format_version=%v: 이 정책은 1.x 만 해석합니다. 갱신 전까지 검사 결과를 신뢰하지 마십시오.", [object.get(input, "format_version", "(없음)")]))

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

# 미확정 경계는 after 에서 빠진다 — "없음" 으로 단정하지 않고 아래 warn 으로 보낸다.
deny contains finding_at("high", sprintf("권한 경계 없는 사용자 생성: `%s`", [rc.address]), "사용자에게 부여되는 권한을 제한할 경계가 없습니다.", rc) if {
	some rc in changes
	rc.type == "aws_iam_user"
	acted(rc, "create")
	not unknown_after_field(rc, "permissions_boundary")
	not boundary(rc, "after")
}

# 경계는 제자리 갱신 대상이라 create 만 보면 변수를 비우는 조용한 update 를 놓친다.
deny contains finding_at("high", boundary_text(rc), "기존 경계가 제한하던 권한이 유효해질 수 있습니다. 교체한 경계의 허용 범위를 확인하십시오.", rc) if {
	some rc in changes
	rc.type in boundary_types
	acted(rc, "update")
	not unknown_after_field(rc, "permissions_boundary")
	boundary_changed(rc)
}

# 역할 생성은 guardrail 이 막는다. 여기서는 사용자 생성과 두 타입의 갱신만 본다.
boundary_watched(rc) if {
	rc.type == "aws_iam_user"
	acted(rc, "create")
}

boundary_watched(rc) if {
	rc.type in boundary_types
	acted(rc, "update")
}

warn contains finding_at("warn", sprintf("권한 경계 미확정: `%s`", [rc.address]), "적용 후 경계를 plan에서 확인할 수 없습니다. 기존 경계와 적용될 경계의 허용 범위를 확인하십시오.", rc) if {
	some rc in changes
	boundary_watched(rc)
	unknown_after_field(rc, "permissions_boundary")
}

boundary_changed(rc) if {
	boundary(rc, "before")
	not boundary(rc, "after")
}

boundary_changed(rc) if boundary(rc, "before") != boundary(rc, "after")

boundary_text(rc) := sprintf("권한 경계 교체 (`%s` → `%s`): `%s`", [boundary(rc, "before"), boundary(rc, "after"), rc.address]) if boundary(rc, "after")

boundary_text(rc) := sprintf("권한 경계 제거: `%s`", [rc.address]) if not boundary(rc, "after")

# ---- 권한 부여 ----------------------------------------------------------

# which 쪽(before·after)에 적힌 관리형 정책 ARN. 미확정 원소는 null 로 오므로 뺀다.
arns_in(rc, which) := {arn |
	some arn in as_array(rc.change[which][arn_field(rc)])
	is_string(arn)
}

# 이번 변경으로 새로 부여되는 ARN. create·import 는 전부, update 는 before 에 없던 것이다.
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

# 일괄 연결 리소스는 users·groups·roles 추가가 update 다. 같은 ARN 이라도 새 주체에게는 부여다.
grants contains {"rc": rc, "arn": arn} if {
	some rc in live
	acted(rc, "update")
	rc.type == "aws_iam_policy_attachment"
	some arn in arns_in(rc, "after")
	some kind in {"users", "groups", "roles"}
	some principal in object.get(rc.change.after, kind, [])
	not principal in object.get(rc.change.before, kind, [])
}

deny contains finding_at("high", sprintf("특권 정책 연결: `%s` → `%s`", [g.arn, g.rc.address]), "관리자·IAM 전체 권한입니다. 이 연결이 의도된 것인지 본문에 사유를 남기십시오.", g.rc) if {
	some g in grants
	regex.match(critical_policy, g.arn)
}

warn contains finding_at("warn", sprintf("광범위한 정책 연결: `%s` → `%s`", [g.arn, g.rc.address]), "해당 서비스 전체 권한입니다. 더 좁은 정책으로 대체할 수 있는지 확인하십시오.", g.rc) if {
	some g in grants
	not regex.match(critical_policy, g.arn)
	regex.match(broad_policy, g.arn)
}

# 미확정 ARN 은 after 에서 빠져 위 두 규칙이 지나간다. 역할의 managed_policy_arns 는 Computed 라
# 미설정 생성에서도 미확정으로 나오므로 연결 리소스만 검토 대상으로 남긴다.
warn contains finding_at("warn", sprintf("정책 연결 미확정: `%s`", [rc.address]), "연결할 정책 ARN 이 plan 시점에 확정되지 않아 특권·광범위 정책 검사를 하지 못했습니다. 적용될 ARN 을 확인하십시오.", rc) if {
	some rc in live
	rc.type in attachment_resources
	unknown_after_field(rc, arn_field(rc))
}

# ---- 정책 본문 ----------------------------------------------------------

# 본문 자리 하나가 {rc, field, doc} 다. 미확정이면 doc 이 null 로 남아 미검사 경고를 받는다.
policy_slots contains {"rc": rc, "field": field, "doc": object.get(rc.change.after, field, null)} if {
	some rc in live
	field := policy_fields[rc.type]
}

# 역할의 inline_policy 블록(deprecated) 도 본문 자리다. 블록 전체는 Computed 라 미설정 생성에서도
# 미확정으로 나오므로 확정된 블록만 본다.
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

warn contains finding_at("warn", sprintf("정책 본문 미검사: `%s.%s`", [slot.rc.address, slot.field]), "본문이 미확정이거나 JSON 정책 문장으로 읽히지 않습니다. 확정된 본문과 Access Analyzer 결과를 확인하십시오.", slot.rc) if {
	some slot in policy_slots
	not readable_policy(slot.doc)
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
	is_string(doc)
	parsed := json.unmarshal(doc)
	some s in as_array(parsed.Statement)
	s.Effect == "Allow"
	"*" in as_array(s.Action)
	"*" in as_array(s.Resource)
}

as_array(x) := x if is_array(x)

as_array(x) := [x] if not is_array(x)

# ---- 정보 ---------------------------------------------------------------

warn contains finding_at("warn", sprintf("그룹 소속 변경: `%s` → %s", [rc.address, groups_text(rc)]), "그룹을 통해 부여되는 권한이 바뀝니다.", rc) if {
	some rc in live
	rc.type == "aws_iam_user_group_membership"
	mutates(rc)
}

# 미확정 그룹은 after 에서 빠지거나 null 원소로 온다. 헤드의 sprintf 가 실패하면 경고 자체가 사라지므로 따로 만든다.
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
