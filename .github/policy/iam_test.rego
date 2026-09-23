# 정책 자체의 단위 테스트. `conftest verify -p .github/policy`
#
# plan JSON 은 값이 없을 때 null 을 쓰는데 Rego 에서 null 은 정의된 값이라
# `not x` 로 걸리지 않는다. 아래 null 관련 테스트는 그 회귀를 막는다.
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

hits(rules, needle) := count([m |
	some f in rules
	m := f.msg
	contains(m, needle)
])

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
	r := deny with input as plan([user(
		"aws_iam_user.member[\"hong\"]", ["update"],
		{"permissions_boundary": BOUNDARY}, {"permissions_boundary": BOUNDARY},
	)])
	hits(r, "권한 경계") == 0
}

# null 은 정의된 값이라 `not x` 로 안 걸린다 — 이 회귀를 막는다.
test_create_with_null_boundary_is_denied if {
	r := deny with input as plan([user(
		"aws_iam_user.member[\"park\"]", ["create"],
		null, {"name": "park", "permissions_boundary": null},
	)])
	hits(r, "권한 경계 없는 사용자 생성") == 1
}

test_create_with_boundary_is_silent if {
	r := deny with input as plan([user(
		"aws_iam_user.member[\"park\"]", ["create"],
		null, {"name": "park", "permissions_boundary": BOUNDARY},
	)])
	hits(r, "권한 경계") == 0
}

# ---- 권한 부여 ----------------------------------------------------------

test_iam_full_access_is_denied if {
	r := deny with input as plan([attach("a", "arn:aws:iam::aws:policy/IAMFullAccess")])
	hits(r, "특권 정책 연결") == 1
}

test_administrator_access_is_denied if {
	r := deny with input as plan([attach("a", "arn:aws:iam::aws:policy/AdministratorAccess")])
	hits(r, "특권 정책 연결") == 1
}

test_read_only_is_not_denied if {
	r := deny with input as plan([attach("a", "arn:aws:iam::aws:policy/ReadOnlyAccess")])
	count(r) == 0
}

test_service_full_access_is_warned_not_denied if {
	d := deny with input as plan([attach("a", "arn:aws:iam::aws:policy/AmazonS3FullAccess")])
	w := warn with input as plan([attach("a", "arn:aws:iam::aws:policy/AmazonS3FullAccess")])
	count(d) == 0
	hits(w, "광범위한 정책 연결") == 1
}

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

# star 규칙은 policy_fields 매핑을 따른다 — 타입마다 문서가 담기는 필드가 다르다.
test_star_policy_follows_field_mapping if {
	r := deny with input as plan([{
		"address": "aws_iam_role.wide",
		"type": "aws_iam_role",
		"change": {
			"actions": ["create"], "before": null,
			"after": {
				"assume_role_policy": json.marshal({"Statement": [{
					"Effect": "Allow", "Action": "*", "Resource": "*",
				}]}),
				"permissions_boundary": BOUNDARY,
			},
		},
	}])
	hits(r, "모든 작업을 허용") == 1
}

test_scoped_policy_is_silent if {
	r := deny with input as plan([{
		"address": "aws_iam_policy.ok",
		"type": "aws_iam_policy",
		"change": {
			"actions": ["create"], "before": null,
			"after": {"policy": "{\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::b/*\"}]}"},
		},
	}])
	count(r) == 0
}

# ---- 파괴적 변경 / 마이그레이션 -----------------------------------------

test_user_delete_is_denied if {
	r := deny with input as plan([user("aws_iam_user.member[\"kim\"]", ["delete"], {"name": "kim"}, null)])
	hits(r, "사용자 삭제") == 1
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
	r := warn with input as plan([{
		"address": "aws_iam_user.member[\"hong\"]",
		"type": "aws_iam_user",
		"change": {
			"actions": ["no-op"], "before": {"name": "hong"},
			"after": {"name": "hong", "permissions_boundary": BOUNDARY},
			"importing": {"id": "hong"},
		},
	}])
	hits(r, "코드로 들여옴") == 1
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
	r := deny with input as plan([user("aws_iam_user.member[\"hong\"]", ["no-op"], {"name": "hong"}, {"name": "hong"})])
	count(r) == 0
}

test_non_iam_is_ignored if {
	r := deny with input as plan([{
		"address": "aws_s3_bucket.b",
		"type": "aws_s3_bucket",
		"change": {"actions": ["delete"], "before": {}, "after": null},
	}])
	count(r) == 0
}

# ---- 형식 버전 ----------------------------------------------------------

test_missing_format_version_is_denied if {
	r := deny with input as {"resource_changes": []}
	hits(r, "형식 버전") == 1
}

test_future_major_is_denied if {
	r := deny with input as {"format_version": "2.0", "resource_changes": []}
	hits(r, "형식 버전") == 1
}

test_minor_bump_is_accepted if {
	r := deny with input as {"format_version": "1.9", "resource_changes": []}
	count(r) == 0
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

test_role_boundary_removal_and_swap_are_denied if {
	every after_val in [{"permissions_boundary": null}, {}, {"permissions_boundary": "arn:aws:iam::123456789012:policy/Other"}] {
		r := deny with input as plan([role_change({"permissions_boundary": BOUNDARY}, after_val, {})])
		hits(r, "권한 경계") == 1
	}
}

test_role_boundary_unchanged_is_silent if {
	value := {"permissions_boundary": BOUNDARY}
	r := deny with input as plan([role_change(value, value, {})])
	hits(r, "권한 경계") == 0
}

test_unknown_boundary_is_warned_without_claiming_removal if {
	every kind in ["aws_iam_user", "aws_iam_role"] {
		every unknown in [{"permissions_boundary": true}, true] {
			rc := object.union(role_change({"permissions_boundary": BOUNDARY}, {}, unknown), {"type": kind})
			d := deny with input as plan([rc])
			w := warn with input as plan([rc])
			hits(d, "권한 경계 제거") == 0
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
		r := deny with input as plan([attachment_update("arn:aws:iam::aws:policy/AdministratorAccess", kind, ["old"], ["old", "new"])])
		hits(r, "특권 정책 연결") == 1
	}
}

test_full_access_attachment_update_is_warned if {
	r := warn with input as plan([attachment_update("arn:aws:iam::aws:policy/AmazonS3FullAccess", "roles", [], ["new"])])
	hits(r, "광범위한 정책 연결") == 1
}

test_attachment_removal_and_reorder_do_not_warn_about_grants if {
	every after_members in [["old"], [], ["new", "old"]] {
		rc := attachment_update("arn:aws:iam::aws:policy/AdministratorAccess", "roles", ["old", "new"], after_members)
		d := deny with input as plan([rc])
		hits(d, "특권 정책 연결") == 0
	}
}

test_admin_attachment_import_is_denied_but_plain_noop_is_not if {
	base := attach("admin", "arn:aws:iam::aws:policy/AdministratorAccess")
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
		w := warn with input as plan([policy_change(["update"], doc)])
		hits(w, "정책 본문 미검사") == 1
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
