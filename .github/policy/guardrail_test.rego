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

BOUNDARY := "arn:aws:iam::446413909569:policy/KintounGuardrailBoundary"

test_compliant_role_passes if {
	count(deny) == 0 with input as plan([role("/project/kintoun/", BOUNDARY)])
}

test_missing_boundary_is_blocked if {
	r := deny with input as plan([role("/project/kintoun/", null)])
	count(r) == 1
}

test_default_path_is_blocked if {
	r := deny with input as plan([role("/", BOUNDARY)])
	count(r) == 1
}

# path 속성이 아예 없어도 막힌다 (fail-closed).
test_absent_path_is_blocked if {
	r := deny with input as plan([{
		"address": "aws_iam_role.svc",
		"type": "aws_iam_role",
		"change": {"actions": ["create"], "before": null, "after": {"permissions_boundary": BOUNDARY}},
	}])
	count(r) == 1
}

test_both_violations_are_two_findings if {
	r := deny with input as plan([role("/", null)])
	count(r) == 2
}

test_noop_role_is_ignored if {
	r := deny with input as plan([{
		"address": "aws_iam_role.svc",
		"type": "aws_iam_role",
		"change": {"actions": ["no-op"], "before": {"path": "/"}, "after": {"path": "/"}},
	}])
	count(r) == 0
}

test_user_is_not_guardrail_scope if {
	r := deny with input as plan([{
		"address": "aws_iam_user.member[\"hong\"]",
		"type": "aws_iam_user",
		"change": {"actions": ["create"], "before": null, "after": {"name": "hong"}},
	}])
	count(r) == 0
}
