# 정책 자체의 단위 테스트. `conftest verify -p .github/policy`
#
# plan JSON 은 값이 없을 때 null 을 쓰는데 Rego 에서 null 은 정의된 값이라
# `not x` 로 걸리지 않는다. 아래 null 관련 테스트는 그 회귀를 막는다.
# 미확정 값은 after 에서 빠지고 after_unknown 에 true 로 온다. 미확정 관련 테스트는
# 규칙이 조용히 지나가거나 "없음" 으로 단정하는 회귀를 막는다.
package terraform.iam

import rego.v1

# ---- 헬퍼 ---------------------------------------------------------------

plan(changes) := {"format_version": "1.2", "resource_changes": changes}

user(addr, actions, before_val, after_val) := {
	"address": addr,
	"type": "aws_iam_user",
	"change": {"actions": actions, "before": before_val, "after": after_val},
}

attach(addr, arn) := {
	"address": addr,
	"type": "aws_iam_group_policy_attachment",
	"change": {"actions": ["create"], "before": null, "after": {"policy_arn": arn}},
}

BOUNDARY := "arn:aws:iam::446413909569:policy/KintounGuardrailBoundary"

ADMIN := "arn:aws:iam::aws:policy/AdministratorAccess"

READ_ONLY := "arn:aws:iam::aws:policy/ReadOnlyAccess"

S3_FULL := "arn:aws:iam::aws:policy/AmazonS3FullAccess"

STAR := json.marshal({"Statement": [{"Effect": "Allow", "Action": "*", "Resource": "*"}]})

SCOPED := json.marshal({"Statement": [{"Effect": "Allow", "Action": "s3:GetObject", "Resource": "arn:aws:s3:::b/*"}]})

hits(rules, needle) := count([m |
	some f in rules
	m := f.msg
	contains(m, needle)
])

with_unknown(rc, unknown) := object.union(rc, {"change": object.union(rc.change, {"after_unknown": unknown})})

# ---- 권한 경계 ----------------------------------------------------------

test_boundary_removed_is_denied if {
	r := deny with input as plan([user(
		"aws_iam_user.member[\"hong\"]", ["update"],
		{"permissions_boundary": BOUNDARY}, {"permissions_boundary": null},
	)])
	hits(r, "권한 경계 제거") == 1
}

test_boundary_swapped_is_denied if {
	r := deny with input as plan([user(
		"aws_iam_user.member[\"hong\"]", ["update"],
		{"permissions_boundary": BOUNDARY}, {"permissions_boundary": "arn:aws:iam::1:policy/Loose"},
	)])
	hits(r, "권한 경계 교체") == 1
}

test_boundary_unchanged_is_silent if {
	p := plan([user(
		"aws_iam_user.member[\"hong\"]", ["update"],
		{"permissions_boundary": BOUNDARY}, {"permissions_boundary": BOUNDARY},
	)])
	hits(deny, "권한 경계") == 0 with input as p
	hits(warn, "권한 경계") == 0 with input as p
}

# null 은 정의된 값이라 `not x` 로 안 걸리고 빈 문자열은 is_string 을 통과한다 — 이 회귀를 막는다.
test_create_with_null_or_empty_boundary_is_denied if {
	every boundary in [null, ""] {
		r := deny with input as plan([user(
			"aws_iam_user.member[\"park\"]", ["create"],
			null, {"name": "park", "permissions_boundary": boundary},
		)])
		hits(r, "권한 경계 없는 사용자 생성") == 1
	}
}

test_create_with_boundary_is_silent if {
	p := plan([user(
		"aws_iam_user.member[\"park\"]", ["create"],
		null, {"name": "park", "permissions_boundary": BOUNDARY},
	)])
	hits(deny, "권한 경계") == 0 with input as p
	hits(warn, "권한 경계") == 0 with input as p
}

# 생성 시 미확정 경계는 "없음" 이 아니다. 갱신과 같은 확인 항목으로 남긴다.
test_create_with_unknown_boundary_is_warned_not_denied if {
	every unknown in [{"permissions_boundary": true}, true] {
		rc := with_unknown(user("aws_iam_user.member[\"park\"]", ["create"], null, {"name": "park"}), unknown)
		hits(deny, "권한 경계") == 0 with input as plan([rc])
		hits(warn, "권한 경계 미확정") == 1 with input as plan([rc])
	}
}

# 역할 생성의 경계는 guardrail 이 차단한다. 자문 패키지가 같은 건을 두 번 적지 않는다.
test_role_create_boundary_is_left_to_guardrail if {
	known := role_create({"path": "/project/x/"}, {})
	unknown := role_create({"path": "/project/x/"}, {"permissions_boundary": true})
	every rc in [known, unknown] {
		hits(deny, "권한 경계") == 0 with input as plan([rc])
		hits(warn, "권한 경계") == 0 with input as plan([rc])
	}
}

# ---- 권한 부여 ----------------------------------------------------------

test_iam_full_access_is_denied if {
	r := deny with input as plan([attach("a", "arn:aws:iam::aws:policy/IAMFullAccess")])
	hits(r, "특권 정책 연결") == 1
}

test_administrator_access_is_denied if {
	r := deny with input as plan([attach("a", ADMIN)])
	hits(r, "특권 정책 연결") == 1
}

test_read_only_is_silent if {
	p := plan([attach("a", READ_ONLY)])
	count(deny) == 0 with input as p
	count(warn) == 0 with input as p
}

test_service_full_access_is_warned_not_denied if {
	p := plan([attach("a", S3_FULL)])
	count(deny) == 0 with input as p
	hits(warn, "광범위한 정책 연결") == 1 with input as p
}

# 연결 ARN 이 바뀌는 갱신은 새 ARN 의 부여다.
test_attachment_arn_swap_on_update_is_checked if {
	rc := {
		"address": "aws_iam_role_policy_attachment.a", "type": "aws_iam_role_policy_attachment",
		"change": {"actions": ["update"], "before": {"policy_arn": READ_ONLY}, "after": {"policy_arn": ADMIN}},
	}
	hits(deny, "특권 정책 연결") == 1 with input as plan([rc])
}

# 미확정 ARN 은 after 에서 빠진다. 조용히 지나가지 않고 확인 항목으로 남긴다.
test_unknown_policy_arn_is_warned_not_silent if {
	every kind in attachment_types {
		every unknown in [{"policy_arn": true}, true] {
			rc := with_unknown({"address": "x", "type": kind, "change": {"actions": ["create"], "before": null, "after": {}}}, unknown)
			hits(deny, "정책 연결") == 0 with input as plan([rc])
			hits(warn, "정책 연결 미확정") == 1 with input as plan([rc])
		}
	}
}

exclusive(kind, actions, before_arns, after_arns) := {
	"address": sprintf("%s.x", [kind]), "type": kind,
	"change": {"actions": actions, "before": before_arns, "after": after_arns},
}

# *_exclusive 리소스는 policy_arns 목록으로 연결한다. 추가만 부여이고 제거·순서 변경은 아니다.
test_exclusive_attachments_follow_arn_field if {
	every kind in exclusive_attachment_types {
		created := exclusive(kind, ["create"], null, {"policy_arns": [READ_ONLY, ADMIN]})
		hits(deny, "특권 정책 연결") == 1 with input as plan([created])
		added := exclusive(kind, ["update"], {"policy_arns": [READ_ONLY]}, {"policy_arns": [READ_ONLY, S3_FULL]})
		hits(warn, "광범위한 정책 연결") == 1 with input as plan([added])
		every after_arns in [[ADMIN], [], [READ_ONLY, ADMIN]] {
			kept := exclusive(kind, ["update"], {"policy_arns": [ADMIN, READ_ONLY]}, {"policy_arns": after_arns})
			hits(deny, "특권 정책 연결") == 0 with input as plan([kept])
		}
	}
}

# 목록 전체나 원소 하나가 미확정이어도 확인 항목으로 남긴다. 미확정 원소는 after 에 null 로 온다.
test_exclusive_unknown_arns_are_warned if {
	every kind in exclusive_attachment_types {
		whole := with_unknown(exclusive(kind, ["create"], null, {}), {"policy_arns": true})
		partial := with_unknown(exclusive(kind, ["create"], null, {"policy_arns": [READ_ONLY, null]}), {"policy_arns": [false, true]})
		every rc in [whole, partial] {
			hits(deny, "정책 연결") == 0 with input as plan([rc])
			hits(warn, "정책 연결 미확정") == 1 with input as plan([rc])
		}
	}
}

role_create(after_val, unknown) := with_unknown(
	{
		"address": "aws_iam_role.worker", "type": "aws_iam_role",
		"change": {"actions": ["create"], "before": null, "after": object.union({"permissions_boundary": BOUNDARY}, after_val)},
	},
	unknown,
)

# 역할의 managed_policy_arns(deprecated) 는 연결 리소스 없이 붙는 자리다.
test_role_managed_policy_arns_are_checked if {
	created := role_create({"managed_policy_arns": [READ_ONLY, ADMIN]}, {})
	r := deny with input as plan([created])
	hits(r, "특권 정책 연결") == 1
	hits(r, sprintf("`%s` → `aws_iam_role.worker`", [ADMIN])) == 1
	added := role_change({"managed_policy_arns": [READ_ONLY]}, {"managed_policy_arns": [READ_ONLY, S3_FULL], "permissions_boundary": BOUNDARY}, {})
	hits(warn, "광범위한 정책 연결") == 1 with input as plan([added])
	removed := role_change({"managed_policy_arns": [READ_ONLY, ADMIN]}, {"managed_policy_arns": [READ_ONLY], "permissions_boundary": BOUNDARY}, {})
	hits(deny, "특권 정책 연결") == 0 with input as plan([removed])
}

# managed_policy_arns 는 Computed 라 미설정 생성에서도 미확정으로 온다. 모든 역할 생성에 경고를 달지 않는다.
test_role_computed_managed_policy_arns_are_not_reported if {
	rc := role_create({}, {"managed_policy_arns": true, "inline_policy": true})
	hits(warn, "정책 연결 미확정") == 0 with input as plan([rc])
	hits(warn, "inline_policy") == 0 with input as plan([rc])
}

# ---- 정책 본문 ----------------------------------------------------------

# Action 과 Resource 는 문자열과 배열 형태 모두 같은 위험으로 판정한다.
test_star_policy_string_and_array_are_denied if {
	every wildcard in ["*", ["*"]] {
		r := deny with input as plan([{
			"address": "aws_iam_policy.wide",
			"type": "aws_iam_policy",
			"change": {
				"actions": ["create"], "before": null,
				"after": {"policy": json.marshal({"Statement": [{
					"Effect": "Allow", "Action": wildcard, "Resource": wildcard,
				}]})},
			},
		}])
		hits(r, "모든 작업을 허용") == 1
	}
}

# 본문 규칙은 policy_fields 매핑을 따른다 — 타입마다 문서가 담기는 필드가 다르다.
test_star_policy_follows_field_mapping if {
	every kind, field in policy_fields {
		rc := {
			"address": sprintf("%s.wide", [kind]), "type": kind,
			"change": {"actions": ["create"], "before": null, "after": {field: STAR, "permissions_boundary": BOUNDARY}},
		}
		r := deny with input as plan([rc])
		hits(r, sprintf("모든 작업을 허용하는 정책: `%s.wide.%s`", [kind, field])) == 1
		hits(warn, "정책 본문 미검사") == 0 with input as plan([rc])
	}
}

# 역할의 inline_policy 블록(deprecated) 은 블록마다 따로 본다.
test_star_inline_policy_is_denied_per_block if {
	rc := role_create({"inline_policy": [{"name": "a", "policy": SCOPED}, {"name": "b", "policy": STAR}]}, {})
	r := deny with input as plan([rc])
	hits(r, "모든 작업을 허용") == 1
	hits(r, "aws_iam_role.worker.inline_policy[1].policy") == 1
}

# 블록의 본문이 미확정이면 그 블록만 미검사다. 빈 목록은 자리가 없다.
test_inline_policy_block_without_document_is_warned if {
	partial := role_create({"inline_policy": [{"name": "a"}]}, {"inline_policy": [{"policy": true}]})
	w := warn with input as plan([partial])
	hits(w, "정책 본문 미검사: `aws_iam_role.worker.inline_policy[0].policy`") == 1
	empty := role_create({"inline_policy": []}, {})
	hits(warn, "inline_policy") == 0 with input as plan([empty])
}

test_scoped_policy_is_silent if {
	p := plan([{
		"address": "aws_iam_policy.ok",
		"type": "aws_iam_policy",
		"change": {"actions": ["create"], "before": null, "after": {"policy": SCOPED}},
	}])
	count(deny) == 0 with input as p
	count(warn) == 0 with input as p
}

# ---- 파괴적 변경 / 마이그레이션 -----------------------------------------

test_user_delete_is_denied if {
	r := deny with input as plan([user("aws_iam_user.member[\"kim\"]", ["delete"], {"name": "kim"}, null)])
	hits(r, "사용자 삭제") == 1
}

# 사용자 외 개체의 삭제는 종류를 가리지 않는다. 교체는 재생성으로만 적는다.
test_non_user_delete_is_denied if {
	every kind in ["aws_iam_role", "aws_iam_group", "aws_iam_policy", "aws_iam_role_policy_attachment"] {
		rc := {"address": sprintf("%s.old", [kind]), "type": kind, "change": {"actions": ["delete"], "before": {}, "after": null}}
		r := deny with input as plan([rc])
		hits(r, "IAM 개체 삭제") == 1
		hits(r, "사용자 삭제") == 0
	}
	replaced := {"address": "aws_iam_role.r", "type": "aws_iam_role", "change": {"actions": ["delete", "create"], "before": {}, "after": {"permissions_boundary": BOUNDARY}}}
	hits(deny, "IAM 개체 삭제") == 0 with input as plan([replaced])
}

test_user_and_group_creation_are_noted if {
	created := user("aws_iam_user.member[\"park\"]", ["create"], null, {"name": "park", "permissions_boundary": BOUNDARY})
	hits(warn, "사용자 생성") == 1 with input as plan([created])
	replaced := user("aws_iam_user.member[\"park\"]", ["delete", "create"], {"name": "park"}, {"name": "park", "permissions_boundary": BOUNDARY})
	hits(warn, "사용자 생성") == 0 with input as plan([replaced])
	group := {"address": "aws_iam_group.ops", "type": "aws_iam_group", "change": {"actions": ["create"], "before": null, "after": {"name": "ops"}}}
	hits(warn, "그룹 생성") == 1 with input as plan([group])
}

test_replace_is_denied_once if {
	r := deny with input as plan([user(
		"aws_iam_user.member[\"kim\"]", ["delete", "create"],
		{"path": "/"}, {"path": "/t/", "permissions_boundary": BOUNDARY},
	)])
	hits(r, "재생성") == 1
	hits(r, "사용자 삭제") == 0
}

# import 는 no-op 으로도 나타난다. 필터에서 지워지면 안 된다.
test_noop_import_is_surfaced if {
	p := plan([{
		"address": "aws_iam_user.member[\"hong\"]",
		"type": "aws_iam_user",
		"change": {
			"actions": ["no-op"], "before": {"name": "hong"},
			"after": {"name": "hong", "permissions_boundary": BOUNDARY},
			"importing": {"id": "hong"},
		},
	}])
	hits(warn, "코드로 들여옴") == 1 with input as p
	count(deny) == 0 with input as p
}

test_import_causing_replace_is_denied if {
	r := deny with input as plan([{
		"address": "aws_iam_user.member[\"kim\"]",
		"type": "aws_iam_user",
		"change": {
			"actions": ["delete", "create"], "before": {"path": "/"},
			"after": {"path": "/t/", "permissions_boundary": BOUNDARY},
			"importing": {"id": "kim"},
		},
	}])
	hits(r, "[import]") == 1
}

test_plain_noop_is_silent if {
	p := plan([user("aws_iam_user.member[\"hong\"]", ["no-op"], {"name": "hong"}, {"name": "hong"})])
	count(deny) == 0 with input as p
	count(warn) == 0 with input as p
}

test_non_iam_is_ignored if {
	p := plan([{
		"address": "aws_s3_bucket.b",
		"type": "aws_s3_bucket",
		"change": {"actions": ["delete"], "before": {}, "after": null},
	}])
	count(deny) == 0 with input as p
	count(warn) == 0 with input as p
}

# ---- 갱신·미확정 값 회귀 -------------------------------------------------

role_change(before_val, after_val, unknown) := {
	"address": "aws_iam_role.worker",
	"type": "aws_iam_role",
	"change": {
		"actions": ["update"], "before": before_val, "after": after_val,
		"after_unknown": unknown,
	},
}

# after_unknown 은 전체(true)·필드(true)·목록·객체 안의 일부 단위로 온다.
test_unknown_after_field_shapes if {
	every unknown in [true, {"x": true}, {"x": [false, true]}, {"x": {"y": [false, {"z": true}]}}] {
		unknown_after_field({"change": {"after_unknown": unknown}}, "x")
	}
	every unknown in [{}, {"x": false}, {"x": [false, false]}, {"x": {"y": {}}}, {"other": true}] {
		not unknown_after_field({"change": {"after_unknown": unknown}}, "x")
	}
	not unknown_after_field({"change": {}}, "x")
}

test_role_boundary_removal_and_swap_are_denied if {
	every after_val in [{"permissions_boundary": null}, {}, {"permissions_boundary": "arn:aws:iam::123456789012:policy/Other"}] {
		r := deny with input as plan([role_change({"permissions_boundary": BOUNDARY}, after_val, {})])
		hits(r, "권한 경계") == 1
	}
}

test_role_boundary_unchanged_is_silent if {
	value := {"permissions_boundary": BOUNDARY}
	p := plan([role_change(value, value, {})])
	hits(deny, "권한 경계") == 0 with input as p
	hits(warn, "권한 경계") == 0 with input as p
}

test_unknown_boundary_is_warned_without_claiming_removal if {
	every kind in boundary_types {
		every unknown in [{"permissions_boundary": true}, true] {
			rc := object.union(role_change({"permissions_boundary": BOUNDARY}, {}, unknown), {"type": kind})
			d := deny with input as plan([rc])
			w := warn with input as plan([rc])
			hits(d, "권한 경계") == 0
			hits(w, "권한 경계 미확정") == 1
		}
	}
}

attachment_update(arn, kind, before_members, after_members) := {
	"address": "aws_iam_policy_attachment.shared",
	"type": "aws_iam_policy_attachment",
	"change": {
		"actions": ["update"],
		"before": {"policy_arn": arn, kind: before_members},
		"after": {"policy_arn": arn, kind: after_members},
	},
}

test_admin_attachment_update_additions_are_denied if {
	every kind in ["users", "groups", "roles"] {
		r := deny with input as plan([attachment_update(ADMIN, kind, ["old"], ["old", "new"])])
		hits(r, "특권 정책 연결") == 1
	}
}

test_full_access_attachment_update_is_warned if {
	r := warn with input as plan([attachment_update(S3_FULL, "roles", [], ["new"])])
	hits(r, "광범위한 정책 연결") == 1
}

test_attachment_removal_and_reorder_do_not_warn_about_grants if {
	every after_members in [["old"], [], ["new", "old"]] {
		rc := attachment_update(ADMIN, "roles", ["old", "new"], after_members)
		hits(deny, "특권 정책 연결") == 0 with input as plan([rc])
		hits(warn, "정책 연결") == 0 with input as plan([rc])
	}
}

test_admin_attachment_import_is_denied_but_plain_noop_is_not if {
	base := attach("admin", ADMIN)
	change := object.union(base.change, {"actions": ["no-op"]})
	plain := object.union(base, {"change": change})
	imported := object.union(base, {"change": object.union(change, {"importing": {"id": "admin"}})})
	d := deny with input as plan([plain])
	i := deny with input as plan([imported])
	hits(d, "특권 정책 연결") == 0
	hits(i, "특권 정책 연결") == 1
}

policy_change(actions, doc) := {
	"address": "aws_iam_policy.example", "type": "aws_iam_policy",
	"change": {"actions": actions, "before": {}, "after": {"policy": doc}},
}

test_replacement_policy_is_checked_after_recreation if {
	every actions in [["delete", "create"], ["create", "delete"]] {
		doc := json.marshal({"Statement": {"Effect": "Allow", "Action": "*", "Resource": "*"}})
		d := deny with input as plan([policy_change(actions, doc)])
		hits(d, "모든 작업을 허용") == 1
		hits(d, "재생성") == 1
	}
}

test_unknown_and_unreadable_policy_documents_are_warned if {
	every doc in [null, "{", "null", "[]", "{}", "{\"Statement\":[null]}"] {
		p := plan([policy_change(["update"], doc)])
		hits(warn, "정책 본문 미검사") == 1 with input as p
		hits(deny, "모든 작업을 허용") == 0 with input as p
	}
}

test_unknown_role_trust_policy_is_warned if {
	rc := role_change({}, {"permissions_boundary": BOUNDARY}, {"assume_role_policy": true})
	w := warn with input as plan([rc])
	hits(w, "aws_iam_role.worker.assume_role_policy") == 1
}

test_readable_policy_is_not_reported_unchecked if {
	every statements in [{"Effect": "Allow", "Action": "s3:GetObject", "Resource": "*"}, [{"Effect": "Allow", "Action": "s3:GetObject", "Resource": "*"}]] {
		w := warn with input as plan([policy_change(["update"], json.marshal({"Statement": statements}))])
		hits(w, "정책 본문 미검사") == 0
	}
}

test_deleted_policy_is_not_reported_unchecked if {
	rc := {"address": "aws_iam_policy.old", "type": "aws_iam_policy", "change": {"actions": ["delete"], "before": {}, "after": null}}
	w := warn with input as plan([rc])
	hits(w, "정책 본문 미검사") == 0
}

# ---- 그룹 소속 ----------------------------------------------------------

membership(actions, before_val, after_val) := {
	"address": "aws_iam_user_group_membership.hong", "type": "aws_iam_user_group_membership",
	"change": {"actions": actions, "before": before_val, "after": after_val},
}

test_membership_change_lists_groups if {
	w := warn with input as plan([membership(["update"], {"groups": ["a"]}, {"groups": ["a", "b"]})])
	hits(w, "그룹 소속 변경: `aws_iam_user_group_membership.hong` → a, b") == 1
	replaced := membership(["delete", "create"], {"groups": ["a"]}, {"groups": ["b"]})
	hits(warn, "그룹 소속 변경") == 1 with input as plan([replaced])
	hits(warn, "그룹 소속 변경") == 0 with input as plan([membership(["delete"], {"groups": ["a"]}, null)])
}

# 미확정 그룹이라도 헤드의 sprintf 가 실패해 경고가 사라지면 안 된다.
test_membership_unknown_groups_still_warned if {
	whole := with_unknown(membership(["create"], null, {"user": "hong"}), {"groups": true})
	partial := with_unknown(membership(["create"], null, {"user": "hong", "groups": ["a", null]}), {"groups": [false, true]})
	every rc in [whole, partial] {
		w := warn with input as plan([rc])
		hits(w, "그룹 소속 변경: `aws_iam_user_group_membership.hong` → (미확정)") == 1
	}
}

# import 만 있는 no-op 은 소속이 바뀌지 않는다. 들여옴 경고만 남긴다.
test_membership_noop_import_is_not_a_change if {
	rc := object.union(membership(["no-op"], {"groups": ["a"]}, {"groups": ["a"]}), {"change": object.union(membership(["no-op"], {"groups": ["a"]}, {"groups": ["a"]}).change, {"importing": {"id": "hong"}})})
	w := warn with input as plan([rc])
	hits(w, "그룹 소속 변경") == 0
	hits(w, "코드로 들여옴") == 1
}
