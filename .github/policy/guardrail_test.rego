package terraform.guardrail

import rego.v1

plan(changes) := {"format_version": "1.2", "resource_changes": changes}

role(path_val, boundary_val) := {
	"address": "aws_iam_role.svc",
	"type": "aws_iam_role",
	"change": {"actions": ["create"], "before": null, "after": {
		"path": path_val,
		"permissions_boundary": boundary_val,
	}},
}

with_unknown(rc, unknown) := object.union(rc, {"change": object.union(rc.change, {"after_unknown": unknown})})

BOUNDARY := "arn:aws:iam::446413909569:policy/KintounGuardrailBoundary"

hits(rules, needle) := count([f | some f in rules; contains(f.msg, needle)])

test_compliant_role_passes if {
	count(deny) == 0 with input as plan([role("/project/kintoun/", BOUNDARY)])
}

test_missing_boundary_is_blocked if {
	every boundary in [null, ""] {
		r := deny with input as plan([role("/project/kintoun/", boundary)])
		count(r) == 1
		hits(r, "권한 경계 없는 롤 생성") == 1
	}
}

# 미확정 경계는 준수를 증명하지 못하므로 막되, "없음" 으로 단정하지 않는다.
test_unknown_boundary_is_blocked_as_unknown if {
	base := {
		"address": "aws_iam_role.svc", "type": "aws_iam_role",
		"change": {"actions": ["create"], "before": null, "after": {"path": "/project/kintoun/"}},
	}
	every unknown in [{"permissions_boundary": true}, true] {
		r := deny with input as plan([with_unknown(base, unknown)])
		count(r) == 1
		hits(r, "권한 경계 미확정 롤 생성") == 1
	}
}

test_default_path_is_blocked if {
	r := deny with input as plan([role("/", BOUNDARY)])
	count(r) == 1
	hits(r, "프로젝트 경로 밖의 롤 생성: `aws_iam_role.svc` (path=/)") == 1
}

# path 속성이 아예 없어도 막힌다 (fail-closed).
test_absent_path_is_blocked if {
	r := deny with input as plan([{
		"address": "aws_iam_role.svc",
		"type": "aws_iam_role",
		"change": {"actions": ["create"], "before": null, "after": {"permissions_boundary": BOUNDARY}},
	}])
	count(r) == 1
	hits(r, "(path=(없음))") == 1
}

test_unknown_path_is_blocked_as_unknown if {
	rc := with_unknown(
		{
			"address": "aws_iam_role.svc",
			"type": "aws_iam_role",
			"change": {"actions": ["create"], "before": null, "after": {"permissions_boundary": BOUNDARY}},
		},
		{"path": true},
	)
	r := deny with input as plan([rc])
	count(r) == 1
	hits(r, "(path=(미확정))") == 1
}

# 교체도 create 를 포함하므로 검사한다.
test_replacement_is_checked if {
	rc := {
		"address": "aws_iam_role.svc", "type": "aws_iam_role",
		"change": {"actions": ["delete", "create"], "before": {"path": "/project/kintoun/", "permissions_boundary": BOUNDARY}, "after": {"path": "/"}},
	}
	r := deny with input as plan([rc])
	hits(r, "권한 경계 없는 롤 생성") == 1
	hits(r, "프로젝트 경로 밖의 롤 생성") == 1
}

test_update_and_noop_role_are_ignored if {
	every actions in [["update"], ["no-op"]] {
		r := deny with input as plan([{
			"address": "aws_iam_role.svc",
			"type": "aws_iam_role",
			"change": {"actions": actions, "before": {"path": "/"}, "after": {"path": "/"}},
		}])
		count(r) == 0
	}
}

test_user_is_not_guardrail_scope if {
	r := deny with input as plan([{
		"address": "aws_iam_user.member[\"hong\"]",
		"type": "aws_iam_user",
		"change": {"actions": ["create"], "before": null, "after": {"name": "hong"}},
	}])
	count(r) == 0
}

# 형식을 못 읽으면 위 규칙이 조용히 빗나가므로 차단으로 멈춘다.
test_unsupported_format_version_is_blocked if {
	every doc in [{"resource_changes": []}, {"format_version": "2.0", "resource_changes": []}] {
		r := deny with input as doc
		count(r) == 1
		hits(r, "형식 버전") == 1
	}
	count(deny) == 0 with input as {"format_version": "1.9", "resource_changes": []}
}
